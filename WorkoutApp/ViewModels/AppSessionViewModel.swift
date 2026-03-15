import Foundation
import SwiftUI

enum AppSessionState: Equatable {
    case loading
    case signedOut
    case profileSetup
    case ready
}

@MainActor
final class AppSessionViewModel: ObservableObject {
    @Published var state: AppSessionState = .loading
    @Published var currentUser: WorkoutCloudUser?
    @Published var errorMessage: String?
    @Published var isSyncing = false

    let authService: WorkoutAuthService
    private let api = WorkoutAPIService.shared
    private let snapshotBuilder = WorkoutSnapshotBuilder()

    init(authService: WorkoutAuthService? = nil) {
        self.authService = authService ?? WorkoutAuthService()

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

        currentUser = user
        updateState(for: user)
        await StoreManager.shared.checkEntitlements()
        if state == .ready {
            await syncSnapshot()
        }
    }

    func loginComplete(user: WorkoutCloudUser) async {
        currentUser = user
        errorMessage = nil
        updateState(for: user)
        await StoreManager.shared.checkEntitlements()
        await syncSnapshot()
    }

    func completeOnboarding(displayName: String, goal: String, experienceLevel: String) async {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Bitte gib einen Namen fuer dein Profil ein."
            return
        }

        let profile = WorkoutProfile(
            displayName: trimmedDisplayName,
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            experienceLevel: experienceLevel,
            timezone: TimeZone.current.identifier
        )
        await syncSnapshot(profileOverride: profile)
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
            self.currentUser = updatedUser
            updateState(for: updatedUser)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncing = false
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme == AppConfig.appScheme,
              url.host == "auth",
              url.path == "/verify",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return
        }

        if let user = await authService.verifyMagicLink(token: token) {
            await loginComplete(user: user)
        } else {
            errorMessage = authService.errorMessage
        }
    }

    func signOut() {
        authService.signOut()
        currentUser = nil
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
        let displayName = user.resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty || user.onboardingCompleted == false {
            state = .profileSetup
        } else {
            state = .ready
        }
    }

    private func seedDebugSessionIfNeeded() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["WORKOUTAPP_DEBUG_AUTH_TOKEN"],
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            WorkoutKeychainService.saveToken(token)
        }
        #endif
    }
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

        let stats = WorkoutCloudStats(
            currentStreak: streaks.current,
            longestStreak: streaks.longest,
            totalWorkouts: sessions.count,
            totalMinutes: sessions.reduce(0) { $0 + ($1.duration ?? 0) } / 60,
            personalRecords: personalRecords.count,
            measurementsLogged: measurements.count,
            lastWorkoutAt: lastWorkout?.completedAt ?? lastWorkout?.startedAt,
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
            weekStartsOn: settings.weekStartsOn
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
