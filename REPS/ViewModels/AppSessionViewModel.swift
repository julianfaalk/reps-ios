import Foundation
import SwiftUI

enum OnboardingPlanStyle: String, Equatable {
    case pushPull
    case pushPullLegs
    case pushPullLegsShoulders
    case highFrequencyPushPullLegs
}

struct OnboardingPlanSummary: Equatable {
    var displayName: String
    var goalFocus: TrainingGoalFocus
    var experienceLevel: String
    var trainingDaysPerWeek: Int
    var sessionLengthMinutes: Int
    var rotationStyle: WorkoutRotationStyle
    var planStyle: OnboardingPlanStyle
}

enum AppSessionState: Equatable {
    case loading
    case signedOut
    case profileSetup
    case planReady
    case ready
}

@MainActor
final class AppSessionViewModel: ObservableObject {
    @Published var state: AppSessionState = .loading
    @Published var currentUser: WorkoutCloudUser?
    @Published var errorMessage: String?
    @Published var isSyncing = false
    @Published var pendingInviteCode: String?
    @Published var requestedTab: Int?
    @Published var onboardingPlanSummary: OnboardingPlanSummary?

    let authService: WorkoutAuthService
    private let api = WorkoutAPIService.shared
    private let db = DatabaseService.shared
    private let snapshotBuilder = WorkoutSnapshotBuilder()
    private let notificationService = NotificationService.shared
    private let localization = LocalizationService.shared
    private let onboardingOfferPendingPrefix = "reps.onboarding.offer.pending."

    init(authService: WorkoutAuthService? = nil) {
        self.authService = authService ?? WorkoutAuthService()
        observePushTokenChanges()

        Task {
            seedDebugSessionIfNeeded()
            await restoreSession()
        }
    }

    func restoreSession() async {
        state = .loading

        guard let user = await authService.restoreSession() else {
            currentUser = nil
            state = .signedOut
            return
        }

        await applyServerState(user)
        await StoreManager.shared.checkEntitlements()
        await refreshStateAfterEntitlementCheck()
        if state == .ready {
            await syncSnapshot()
            await syncCurrentDevice()
        }
    }

    func loginComplete(user: WorkoutCloudUser) async {
        await applyServerState(user)
        errorMessage = nil
        await StoreManager.shared.checkEntitlements()
        await refreshStateAfterEntitlementCheck()
        await syncSnapshot()
        await syncCurrentDevice()
    }

    func completeOnboarding(
        displayName: String,
        goal: String,
        experienceLevel: String,
        localSettings: AppSettings? = nil
    ) async {
        let fallbackDisplayName = currentUser?.resolvedDisplayName ?? ""
        let trimmedDisplayName = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? fallbackDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) : displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if var localSettings {
            do {
                let hasPremiumAccess = StoreManager.shared.isPremium || (currentUser?.isPremiumActive ?? false)
                localSettings.trainingSetupCompleted = true
                localSettings.personalPlanLocked = !hasPremiumAccess
                try db.saveSettings(localSettings)
                let summary = try buildOnboardingPlanSummary(
                    displayName: trimmedDisplayName,
                    experienceLevel: experienceLevel,
                    settings: localSettings
                )
                onboardingPlanSummary = summary

                if localSettings.workoutReminderEnabled {
                    let schedule = try db.fetchScheduleWithTemplates()
                    await NotificationService.shared.scheduleWorkoutReminders(
                        for: schedule,
                        at: localSettings.workoutReminderTime,
                        goalFocus: localSettings.goalFocusValue
                    )
                } else {
                    NotificationService.shared.cancelWorkoutReminders()
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        let profile = WorkoutProfile(
            displayName: trimmedDisplayName,
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            experienceLevel: experienceLevel,
            timezone: TimeZone.current.identifier
        )
        await syncSnapshot(profileOverride: profile)
        await StoreManager.shared.checkEntitlements()

        guard errorMessage == nil, let currentUser else { return }

        if StoreManager.shared.isPremium || currentUser.isPremiumActive {
            markPostOnboardingOfferPending(false, for: currentUser)
            await unlockPersonalizedPlanIfNeeded(forceSync: true)
            onboardingPlanSummary = nil
            requestedTab = 0
        } else {
            markPostOnboardingOfferPending(true, for: currentUser)
        }

        await refreshStateAfterEntitlementCheck()
    }

    func completePostOnboardingOffer() {
        guard let currentUser else { return }
        markPostOnboardingOfferPending(false, for: currentUser)
        requestedTab = 0
        updateState(for: currentUser)
    }

    func completePremiumUnlock() async {
        guard let currentUser else { return }
        markPostOnboardingOfferPending(false, for: currentUser)
        await unlockPersonalizedPlanIfNeeded(forceSync: true)
        onboardingPlanSummary = nil
        requestedTab = 0
        await refreshStateAfterEntitlementCheck()
    }

    func syncSnapshot(profileOverride: WorkoutProfile? = nil) async {
        guard let currentUser else { return }

        isSyncing = true
        errorMessage = nil

        do {
            let request = try snapshotBuilder.buildRequest(
                currentUser: currentUser,
                profileOverride: profileOverride
            )
            let updatedUser = try await api.syncMe(request)
            await applyServerState(updatedUser)
            await syncCurrentDevice()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme == AppConfig.appScheme,
              let host = url.host else {
            if handleInviteURL(url) {
                return
            }
            return
        }

        if let tab = routeTab(for: host) {
            requestedTab = tab
            if host == "invite" {
                _ = handleInviteURL(url)
            }
            return
        }

        if host == "auth",
           url.path == "/verify",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            if let user = await authService.verifyMagicLink(token: token) {
                await loginComplete(user: user)
            } else {
                errorMessage = authService.errorMessage
            }
            return
        }

        _ = handleInviteURL(url)
    }

    func signOut() {
        authService.signOut()
        currentUser = nil
        onboardingPlanSummary = nil
        state = .signedOut
    }

    func deleteAccount() async {
        do {
            try await api.deleteAccount()
            signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateState(for user: WorkoutCloudUser) {
        if user.onboardingCompleted == false {
            state = .profileSetup
        } else if shouldPresentPostOnboardingOffer(for: user) {
            if onboardingPlanSummary == nil {
                onboardingPlanSummary = try? rebuildPendingOnboardingSummary(for: user)
            }
            state = onboardingPlanSummary == nil ? .ready : .planReady
        } else {
            state = .ready
        }
    }

    func consumePendingInviteCode() -> String? {
        defer { pendingInviteCode = nil }
        return pendingInviteCode
    }

    func syncCurrentDevice() async {
        guard state == .ready else { return }
        guard currentUser != nil else { return }

        let settings = (try? db.fetchSettings()) ?? AppSettings()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        do {
            try await api.upsertCurrentDevice(
                WorkoutDeviceRegistrationRequest(
                    deviceId: notificationService.currentDeviceID,
                    platform: "ios",
                    appVersion: version,
                    build: build,
                    locale: localization.selectedLanguage.localeIdentifier,
                    timezone: TimeZone.current.identifier,
                    pushToken: notificationService.currentAPNsToken ?? "",
                    pushPermission: await notificationService.currentPermissionStatus(),
                    motivationPushEnabled: settings.motivationPushEnabled,
                    socialPushEnabled: settings.socialPushEnabled
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observePushTokenChanges() {
        NotificationCenter.default.addObserver(
            forName: .workoutAPNsTokenDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.syncCurrentDevice()
            }
        }
    }

    private func applyServerState(_ user: WorkoutCloudUser) async {
        currentUser = user
        await applyRemoteSettings(from: user)
        updateState(for: user)
        if state == .ready, pendingInviteCode != nil {
            requestedTab = 2
        }
    }

    private func applyRemoteSettings(from user: WorkoutCloudUser) async {
        var settings = (try? db.fetchSettings()) ?? AppSettings()
        settings.defaultRestTime = user.preferences.defaultRestTime
        settings.workoutReminderEnabled = user.preferences.workoutReminderEnabled
        settings.restTimerSound = user.preferences.restTimerSound
        settings.restTimerHaptic = user.preferences.restTimerHaptic
        settings.weekStartsOn = user.preferences.weekStartsOn
        settings.trainingSetupCompleted = user.onboardingCompleted
        settings.goalFocus = user.preferences.goalFocus
        settings.preferredSessionLengthMinutes = user.preferences.preferredSessionLengthMinutes
        settings.targetTrainingDaysPerWeek = user.preferences.targetTrainingDaysPerWeek
        settings.rotationStyle = user.preferences.rotationStyle
        settings.personalPlanLocked = user.preferences.personalPlanLocked
        settings.preferredLanguage = user.preferences.preferredLanguage
        settings.motivationPushEnabled = user.preferences.motivationPushEnabled
        settings.socialPushEnabled = user.preferences.socialPushEnabled
        settings.socialVisibility = user.preferences.socialVisibility
        settings.quietHoursStart = user.preferences.quietHoursStart
        settings.quietHoursEnd = user.preferences.quietHoursEnd

        let timeParts = user.preferences.workoutReminderTime.split(separator: ":")
        if timeParts.count == 2,
           let hour = Int(timeParts[0]),
           let minute = Int(timeParts[1]) {
            settings.workoutReminderTime = Calendar.current.date(
                from: DateComponents(hour: hour, minute: minute)
            ) ?? settings.workoutReminderTime
        }

        do {
            try db.saveSettings(settings)
            localization.apply(settings: settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleInviteURL(_ url: URL) -> Bool {
        if url.scheme == AppConfig.appScheme,
           url.host == "invite",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingInviteCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            requestedTab = 2
            return true
        }

        guard let host = url.host,
              host.contains("julianfalk.dev") else {
            return false
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let inviteIndex = pathComponents.firstIndex(of: "invite"),
              inviteIndex + 1 < pathComponents.count else {
            return false
        }

        let code = pathComponents[inviteIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return false }
        pendingInviteCode = code
        requestedTab = 2
        return true
    }

    private func routeTab(for host: String) -> Int? {
        switch host {
        case "today":
            return 0
        case "schedule":
            return 1
        case "friends", "invite":
            return 2
        case "progress":
            return 3
        case "profile", "settings":
            return 4
        default:
            return nil
        }
    }

    private func seedDebugSessionIfNeeded() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["REPS_DEBUG_AUTH_TOKEN"],
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            WorkoutKeychainService.saveToken(token)
        }
        #endif
    }

    private func refreshStateAfterEntitlementCheck() async {
        guard let currentUser else { return }

        if StoreManager.shared.isPremium || currentUser.isPremiumActive {
            markPostOnboardingOfferPending(false, for: currentUser)
            await unlockPersonalizedPlanIfNeeded(forceSync: true)
            onboardingPlanSummary = nil
        } else if onboardingPlanSummary == nil,
                  (shouldPresentPostOnboardingOffer(for: currentUser) || shouldKeepLockedPlanSummary(for: currentUser)) {
            onboardingPlanSummary = try? rebuildPendingOnboardingSummary(for: currentUser)
        }

        updateState(for: currentUser)
    }

    private func shouldPresentPostOnboardingOffer(for user: WorkoutCloudUser) -> Bool {
        isPostOnboardingOfferPending(for: user) && !StoreManager.shared.isPremium && !user.isPremiumActive
    }

    private func isPostOnboardingOfferPending(for user: WorkoutCloudUser) -> Bool {
        guard let key = onboardingOfferTrackingKey(for: user) else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func markPostOnboardingOfferPending(_ isPending: Bool, for user: WorkoutCloudUser) {
        guard let key = onboardingOfferTrackingKey(for: user) else { return }
        UserDefaults.standard.set(isPending, forKey: key)
    }

    private func onboardingOfferTrackingKey(for user: WorkoutCloudUser) -> String? {
        let rawIdentifier = user.id ?? user.email ?? user.resolvedDisplayName
        let trimmedIdentifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return nil }
        return onboardingOfferPendingPrefix + trimmedIdentifier
    }

    private func rebuildPendingOnboardingSummary(for user: WorkoutCloudUser) throws -> OnboardingPlanSummary {
        let settings = try db.fetchSettings()
        return try buildOnboardingPlanSummary(
            displayName: user.resolvedDisplayName,
            experienceLevel: user.profile.experienceLevel,
            settings: settings
        )
    }

    private func shouldKeepLockedPlanSummary(for user: WorkoutCloudUser) -> Bool {
        guard user.onboardingCompleted else { return false }
        guard let settings = try? db.fetchSettings() else { return false }
        return settings.personalPlanLocked
    }

    private func unlockPersonalizedPlanIfNeeded(forceSync: Bool) async {
        guard let currentUser else { return }

        do {
            var settings = try db.fetchSettings()
            guard settings.trainingSetupCompleted, settings.personalPlanLocked else { return }

            _ = try configurePersonalizedSchedule(
                using: settings,
                displayName: currentUser.resolvedDisplayName,
                experienceLevel: currentUser.profile.experienceLevel
            )
            settings.personalPlanLocked = false
            try db.saveSettings(settings)

            if forceSync {
                await syncSnapshot()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configurePersonalizedSchedule(
        using settings: AppSettings,
        displayName: String,
        experienceLevel: String
    ) throws -> OnboardingPlanSummary {
        let descriptor = try personalizedPlanDescriptor(for: settings)

        for dayOfWeek in 0..<7 {
            if let scheduledDay = descriptor.scheduledDays.first(where: { $0.dayOfWeek == dayOfWeek }) {
                try db.saveSchedule(
                    Schedule(
                        dayOfWeek: dayOfWeek,
                        templateId: scheduledDay.templateID,
                        isRestDay: false
                    )
                )
            } else {
                try db.saveSchedule(
                    Schedule(
                        dayOfWeek: dayOfWeek,
                        templateId: nil,
                        isRestDay: true
                    )
                )
            }
        }

        return OnboardingPlanSummary(
            displayName: displayName,
            goalFocus: settings.goalFocusValue,
            experienceLevel: experienceLevel,
            trainingDaysPerWeek: settings.targetTrainingDaysPerWeek,
            sessionLengthMinutes: settings.preferredSessionLengthMinutes,
            rotationStyle: settings.rotationStyleValue,
            planStyle: descriptor.style
        )
    }

    private func buildOnboardingPlanSummary(
        displayName: String,
        experienceLevel: String,
        settings: AppSettings
    ) throws -> OnboardingPlanSummary {
        let descriptor = try personalizedPlanDescriptor(for: settings)
        return OnboardingPlanSummary(
            displayName: displayName,
            goalFocus: settings.goalFocusValue,
            experienceLevel: experienceLevel,
            trainingDaysPerWeek: settings.targetTrainingDaysPerWeek,
            sessionLengthMinutes: settings.preferredSessionLengthMinutes,
            rotationStyle: settings.rotationStyleValue,
            planStyle: descriptor.style
        )
    }

    private func personalizedPlanDescriptor(for settings: AppSettings) throws -> OnboardingPlanScheduleDescriptor {
        let templates = try db.fetchAllTemplates()
        var templateByKind: [OnboardingTemplateKind: WorkoutTemplate] = [:]

        for template in templates {
            guard let kind = templateKind(for: template), templateByKind[kind] == nil else { continue }
            templateByKind[kind] = template
        }

        let trainingDays = max(2, min(6, settings.targetTrainingDaysPerWeek))
        let templateKinds: [OnboardingTemplateKind]
        let weekdays: [Int]
        let style: OnboardingPlanStyle

        switch trainingDays {
        case 2:
            templateKinds = [.push, .pull]
            weekdays = [1, 4]
            style = .pushPull
        case 3:
            templateKinds = [.push, .pull, .legs]
            weekdays = [1, 3, 5]
            style = .pushPullLegs
        case 4:
            templateKinds = [.push, .pull, .legs, .shoulders]
            weekdays = [1, 2, 4, 5]
            style = .pushPullLegsShoulders
        case 5:
            if settings.goalFocusValue == .athletic {
                templateKinds = [.push, .pull, .legs, .shoulders, .pull]
            } else {
                templateKinds = [.push, .pull, .legs, .push, .shoulders]
            }
            weekdays = [1, 2, 3, 5, 6]
            style = .highFrequencyPushPullLegs
        default:
            if settings.goalFocusValue == .athletic {
                templateKinds = [.push, .pull, .legs, .shoulders, .push, .pull]
            } else {
                templateKinds = [.push, .pull, .legs, .push, .pull, .legs]
            }
            weekdays = [1, 2, 3, 4, 5, 6]
            style = .highFrequencyPushPullLegs
        }

        let scheduledDays = zip(weekdays, templateKinds).compactMap { weekday, kind -> OnboardingPlanDay? in
            guard let template = templateByKind[kind] else { return nil }
            return OnboardingPlanDay(dayOfWeek: weekday, templateID: template.id)
        }

        guard scheduledDays.count == templateKinds.count else {
            throw NSError(
                domain: "AppSessionViewModel",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "REPS could not build the default training split."]
            )
        }

        return OnboardingPlanScheduleDescriptor(style: style, scheduledDays: scheduledDays)
    }

    private func templateKind(for template: WorkoutTemplate) -> OnboardingTemplateKind? {
        let name = template.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if name.contains("push") || name.contains("brust") {
            return .push
        }
        if name.contains("pull") || name.contains("rucken") {
            return .pull
        }
        if name.contains("legs") || name.contains("bein") {
            return .legs
        }
        if name.contains("shoulder") || name.contains("schulter") || name.contains("core") {
            return .shoulders
        }

        return nil
    }
}

private struct OnboardingPlanScheduleDescriptor {
    var style: OnboardingPlanStyle
    var scheduledDays: [OnboardingPlanDay]
}

private struct OnboardingPlanDay {
    var dayOfWeek: Int
    var templateID: UUID
}

private enum OnboardingTemplateKind {
    case push
    case pull
    case legs
    case shoulders
}

private struct WorkoutSnapshotBuilder {
    private let db = DatabaseService.shared

    func buildRequest(
        currentUser: WorkoutCloudUser,
        profileOverride: WorkoutProfile? = nil
    ) throws -> WorkoutSyncRequest {
        let settings = try db.fetchSettings()
        let sessions = try db.fetchAllSessions()
            .filter(\.isCompleted)
            .sorted { $0.startedAt < $1.startedAt }
        let measurements = try db.fetchAllMeasurements()
        let personalRecords = try db.fetchAllPersonalRecords()
        let recentSessions = try db.fetchRecentSessions(limit: 1)

        let workoutDays = uniqueWorkoutDays(from: sessions)
        let streaks = calculateStreaks(from: workoutDays)
        let lastWorkout = sessions.last
        let recentWorkoutDates = Array(workoutDays.suffix(30)).map {
            Self.dayFormatter.string(from: $0)
        }
        let weeklySessions = sessions.filter { session in
            guard let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return false }
            let referenceDate = session.completedAt ?? session.startedAt
            return weekInterval.contains(referenceDate)
        }
        let weeklyMinutes = weeklySessions.reduce(0) { $0 + ($1.duration ?? 0) } / 60

        let stats = WorkoutCloudStats(
            currentStreak: streaks.current,
            longestStreak: streaks.longest,
            totalWorkouts: sessions.count,
            totalMinutes: sessions.reduce(0) { $0 + ($1.duration ?? 0) } / 60,
            weeklySessions: weeklySessions.count,
            weeklyMinutes: weeklyMinutes,
            personalRecords: personalRecords.count,
            measurementsLogged: measurements.count,
            lastWorkoutAt: lastWorkout?.completedAt ?? lastWorkout?.startedAt,
            lastWorkoutDurationMinutes: (lastWorkout?.duration ?? 0) / 60,
            lastWorkoutTemplate: recentSessions.first?.template?.name ?? "",
            currentWeightKg: measurements.first?.bodyWeight,
            bodyFatPercentage: measurements.first?.bodyFat,
            recentWorkoutDates: recentWorkoutDates,
            syncedAt: nil
        )

        let preferences = WorkoutCloudPreferences(
            defaultRestTime: settings.defaultRestTime,
            workoutReminderEnabled: settings.workoutReminderEnabled,
            workoutReminderTime: Self.timeString(from: settings.workoutReminderTime),
            restTimerSound: settings.restTimerSound,
            restTimerHaptic: settings.restTimerHaptic,
            weekStartsOn: settings.weekStartsOn,
            goalFocus: settings.goalFocus,
            targetTrainingDaysPerWeek: settings.targetTrainingDaysPerWeek,
            preferredSessionLengthMinutes: settings.preferredSessionLengthMinutes,
            rotationStyle: settings.rotationStyle,
            personalPlanLocked: settings.personalPlanLocked,
            preferredLanguage: settings.preferredLanguage,
            motivationPushEnabled: settings.motivationPushEnabled,
            socialPushEnabled: settings.socialPushEnabled,
            socialVisibility: settings.socialVisibility,
            quietHoursStart: settings.quietHoursStart,
            quietHoursEnd: settings.quietHoursEnd
        )

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        var profile = profileOverride ?? currentUser.profile
        if profile.displayName.isEmpty {
            profile.displayName = currentUser.resolvedDisplayName
        }
        if profile.timezone.isEmpty {
            profile.timezone = TimeZone.current.identifier
        }

        return WorkoutSyncRequest(
            profile: profile,
            preferences: preferences,
            stats: stats,
            device: WorkoutDeviceSnapshot(
                platform: "ios",
                appVersion: version,
                build: build,
                syncedAt: nil
            )
        )
    }

    private func uniqueWorkoutDays(from sessions: [WorkoutSession]) -> [Date] {
        let calendar = Calendar.current
        let unique = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        return unique.sorted()
    }

    private func calculateStreaks(from workoutDays: [Date]) -> (current: Int, longest: Int) {
        guard !workoutDays.isEmpty else { return (0, 0) }

        let calendar = Calendar.current
        var longest = 1
        var running = 1

        for index in 1..<workoutDays.count {
            if let previousDay = calendar.date(byAdding: .day, value: 1, to: workoutDays[index - 1]),
               calendar.isDate(previousDay, inSameDayAs: workoutDays[index]) {
                running += 1
            } else {
                longest = max(longest, running)
                running = 1
            }
        }
        longest = max(longest, running)

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard let lastWorkoutDay = workoutDays.last,
              calendar.isDate(lastWorkoutDay, inSameDayAs: today) || calendar.isDate(lastWorkoutDay, inSameDayAs: yesterday) else {
            return (0, longest)
        }

        var current = 1
        var cursor = lastWorkoutDay
        for day in workoutDays.dropLast().reversed() {
            guard let expectedPreviousDay = calendar.date(byAdding: .day, value: -1, to: cursor),
                  calendar.isDate(day, inSameDayAs: expectedPreviousDay) else {
                break
            }
            current += 1
            cursor = day
        }

        return (current, longest)
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
