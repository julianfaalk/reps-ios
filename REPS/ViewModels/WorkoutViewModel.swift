import Foundation
import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var currentDayPlan: WorkoutDayPlanWithExercises?
    @Published var currentExerciseIndex: Int = 0
    @Published var templateExercises: [TemplateExerciseDetail] = []
    @Published var completedSets: [SessionSet] = []
    @Published var cardioSessions: [CardioSession] = []

    @Published var workoutDuration: Int = 0
    @Published var restTimeRemaining: Int = 0
    @Published var restTimerTotalTime: Int = 0
    @Published var isRestTimerActive: Bool = false
    @Published var warmupTimeRemaining: Int = 0
    @Published var warmupTimerTotalTime: Int = 0
    @Published var isWarmupTimerActive: Bool = false
    @Published var isWorkoutActive: Bool = false

    @Published var sessionNotes: String = ""
    @Published var newPRs: [PersonalRecord] = []

    @Published var errorMessage: String?

    // Track last entered values per exercise during this session
    private var lastEnteredValues: [UUID: (reps: Int?, weight: Double?)] = [:]

    private let db: DatabaseService
    private let planGenerator = WorkoutPlanGenerator()
    private var workoutTimer: Timer?
    private var restTimer: Timer?
    private var warmupTimer: Timer?
    private var defaultRestTime: Int = 90
#if canImport(ActivityKit)
    private var currentActivity: Activity<WorkoutActivityAttributes>?
#endif
    private let categoryVariantKeyPrefix = "workout.variation.category.last."
    private let warmupCardioTag = "[warmup]"
    private let sessionExerciseCachePrefix = "workout.session.exercises."
    private let sessionIndexCachePrefix = "workout.session.index."
    private let sessionWarmupSkipCachePrefix = "workout.session.warmup.skip."
    private let sessionWarmupEndCachePrefix = "workout.session.warmup.end."
    private let sessionWarmupTotalCachePrefix = "workout.session.warmup.total."
    private let sessionWarmupTypeCachePrefix = "workout.session.warmup.type."

    // Timestamps for background persistence
    private var workoutStartTime: Date?
    private var workoutPausedDuration: Int = 0
    private var restTimerEndTime: Date?
    private var warmupTimerEndTime: Date?
    private var warmupCardioTypeInProgress: CardioType?
    private var hasSkippedWarmup = false

    var currentExercise: TemplateExerciseDetail? {
        guard currentExerciseIndex < templateExercises.count else { return nil }
        return templateExercises[currentExerciseIndex]
    }

    var completedSetsForCurrentExercise: [SessionSet] {
        guard let current = currentExercise else { return [] }
        return completedSets.filter { $0.exerciseId == current.exercise.id }
    }

    var isLastExercise: Bool {
        currentExerciseIndex >= templateExercises.count - 1
    }

    var hasLoggedWarmup: Bool {
        cardioSessions.contains { session in
            guard let notes = session.notes?.lowercased() else { return false }
            return notes.contains(warmupCardioTag)
        }
    }

    var hasSatisfiedWarmupRequirement: Bool {
        hasLoggedWarmup || hasSkippedWarmup
    }

    var canShuffleCurrentWorkout: Bool {
        currentDayPlan != nil && completedSets.isEmpty
    }

    var currentPlanExercises: [WorkoutDayPlanExerciseDetail] {
        currentDayPlan?.exercises ?? []
    }

    init(db: DatabaseService = .shared) {
        self.db = db
        loadSettings()
        setupBackgroundObservers()
        Task { @MainActor in
            await restoreActiveSessionIfNeeded()
        }
    }

    private func loadSettings() {
        do {
            let settings = try db.fetchSettings()
            defaultRestTime = settings.defaultRestTime
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setupBackgroundObservers() {
#if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillResignActive()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidBecomeActive()
            }
        }
#endif
    }

    private func handleAppWillResignActive() {
        persistSessionStateCache()
    }

    private func handleAppDidBecomeActive() {
        // Recalculate workout duration from persisted session start time
        if isWorkoutActive, let startTime = currentSession?.startedAt ?? workoutStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            workoutDuration = max(0, elapsed)
        }

        // Recalculate rest timer from end time
        if isRestTimerActive, let endTime = restTimerEndTime {
            let remaining = Int(endTime.timeIntervalSince(Date()))
            if remaining > 0 {
                restTimeRemaining = remaining
            } else {
                // Timer finished while in background
                stopRestTimer()
                triggerRestTimerEnd()
            }
        }

        if isWarmupTimerActive, let endTime = warmupTimerEndTime {
            let remaining = Int(ceil(endTime.timeIntervalSince(Date())))
            if remaining > 0 {
                warmupTimeRemaining = remaining
            } else {
                Task { @MainActor in
                    await finalizeWarmupTimerIfNeeded()
                }
            }
        }
    }

    // MARK: - Last Entered Values

    func getLastEnteredValues(for exerciseId: UUID) -> (reps: Int?, weight: Double?) {
        return lastEnteredValues[exerciseId] ?? (nil, nil)
    }

    func setLastEnteredValues(for exerciseId: UUID, reps: Int?, weight: Double?) {
        lastEnteredValues[exerciseId] = (reps, weight)
    }

    // MARK: - Session Management

    func startSession(templateId: UUID?) async {
        do {
            if let templateId = templateId {
                let dayPlan = try loadOrCreateDayPlan(templateId: templateId, date: Date())
                await startSession(dayPlan: dayPlan)
            } else {
                try startAdHocSessionInternal()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAdHocSession() async {
        do {
            try startAdHocSessionInternal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startSession(dayPlan: WorkoutDayPlanWithExercises) async {
        do {
            try startSessionInternal(dayPlan: dayPlan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAdHocSessionInternal() throws {
        let session = WorkoutSession(templateId: nil, dayPlanId: nil)
        try db.saveSession(session)

        currentSession = session
        currentDayPlan = nil
        templateExercises = []
        currentExerciseIndex = 0
        completedSets = []
        cardioSessions = []
        workoutDuration = 0
        workoutPausedDuration = 0
        workoutStartTime = session.startedAt
        sessionNotes = ""
        newPRs = []
        lastEnteredValues = [:]
        resetWarmupState()
        isWorkoutActive = true

        startWorkoutTimer()
        persistSessionStateCache()
        startLiveActivity(templateName: "Free Workout")
    }

    private func startSessionInternal(dayPlan: WorkoutDayPlanWithExercises) throws {
        let session = WorkoutSession(templateId: dayPlan.template.id, dayPlanId: dayPlan.plan.id)
        try db.saveSession(session)

        currentSession = session
        currentDayPlan = dayPlan
        currentExerciseIndex = 0
        completedSets = []
        cardioSessions = []
        workoutDuration = 0
        workoutPausedDuration = 0
        workoutStartTime = session.startedAt
        sessionNotes = ""
        newPRs = []
        lastEnteredValues = [:]
        resetWarmupState()
        templateExercises = try applyPersistedExerciseDefaults(
            to: dayPlan.exercises.map(\.asTemplateExerciseDetail)
        )
        isWorkoutActive = true

        startWorkoutTimer()
        persistSessionStateCache()
        startLiveActivity(templateName: dayPlan.template.name)
    }

    private func loadOrCreateDayPlan(templateId: UUID, date: Date) throws -> WorkoutDayPlanWithExercises {
        guard let template = try db.fetchTemplate(id: templateId) else {
            throw NSError(
                domain: "WorkoutViewModel",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "The selected template could not be found."]
            )
        }

        let normalizedDate = Calendar.current.startOfDay(for: date)
        let existingPlan = try db.fetchWorkoutDayPlan(date: normalizedDate, templateId: templateId)
        if let existingPlan {
            let exercises = existingPlan.exercises.map(\.exercise)
            if planGenerator.supportsSavedPlan(template: template, exercises: exercises) {
                return existingPlan
            }
        }

        let settings = try db.fetchSettings()
        let rotationStyle = settings.rotationStyleValue
        let completedTemplateSessions = try db.fetchCompletedSessionCount(templateId: templateId, before: normalizedDate)

        if rotationStyle.cadenceSessions > 1,
           completedTemplateSessions > 0,
           completedTemplateSessions % rotationStyle.cadenceSessions != 0,
           let latestPlan = try db.fetchLatestWorkoutDayPlan(templateId: templateId, before: normalizedDate),
           planGenerator.supportsSavedPlan(template: template, exercises: latestPlan.exercises.map(\.exercise)) {
            return try db.saveWorkoutDayPlan(
                date: normalizedDate,
                template: template,
                exercises: dayPlanDrafts(from: latestPlan),
                shuffleCount: 0,
                existingPlanId: existingPlan?.plan.id
            )
        }

        let baseExercises = try db.fetchTemplateExercises(templateId: templateId)
        let allExercises = try db.fetchAllExercises()
        let previousPlan = try db.fetchLatestPlanSnapshot(templateId: templateId, before: normalizedDate)
            ?? db.fetchLatestCompletedSessionSnapshot(templateId: templateId, before: normalizedDate)
        let build = try planGenerator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: previousPlan,
            shuffleSeed: rotationSeed(
                completedSessionCount: completedTemplateSessions,
                style: rotationStyle
            )
        )

        return try db.saveWorkoutDayPlan(
            date: normalizedDate,
            template: template,
            exercises: build.exercises,
            shuffleCount: 0,
            existingPlanId: existingPlan?.plan.id
        )
    }

    func completeSession() async -> SessionWithDetails? {
        guard var session = currentSession else { return nil }

        stopWorkoutTimer()
        stopRestTimer()
        stopWarmupTimer()
        endLiveActivity()

        session.completedAt = Date()
        session.duration = max(workoutDuration, Int(session.completedAt?.timeIntervalSince(session.startedAt) ?? 0))
        session.notes = sessionNotes.isEmpty ? nil : sessionNotes

        do {
            try db.saveSession(session)
            clearSessionStateCache(sessionId: session.id)
            currentSession = nil
            currentDayPlan = nil
            isWorkoutActive = false

            return try db.fetchSessionWithDetails(id: session.id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func cancelSession() {
        stopWorkoutTimer()
        stopRestTimer()
        stopWarmupTimer()
        endLiveActivity()

        if let session = currentSession {
            try? db.deleteSession(session)
            clearSessionStateCache(sessionId: session.id)
        }

        currentSession = nil
        currentDayPlan = nil
        isWorkoutActive = false
        templateExercises = []
        completedSets = []
        cardioSessions = []
    }

    func shuffleCurrentWorkout() async -> String? {
        guard completedSets.isEmpty else {
            return "Shuffle is only available before you log the first set."
        }

        guard let currentDayPlan else {
            return "This workout was not started from a generated day plan."
        }

        do {
            let baseExercises = try db.fetchTemplateExercises(templateId: currentDayPlan.template.id)
            let allExercises = try db.fetchAllExercises()
            let previousPlan = snapshots(from: currentDayPlan)
            let nextShuffleCount = currentDayPlan.plan.shuffleCount + 1
            let build = try planGenerator.buildPlan(
                template: currentDayPlan.template,
                baseExercises: baseExercises,
                allExercises: allExercises,
                previousPlan: previousPlan,
                shuffleSeed: nextShuffleCount
            )

            let updatedPlan = try db.saveWorkoutDayPlan(
                date: currentDayPlan.plan.date,
                template: currentDayPlan.template,
                exercises: build.exercises,
                shuffleCount: nextShuffleCount,
                existingPlanId: currentDayPlan.plan.id
            )

            self.currentDayPlan = updatedPlan
            lastEnteredValues = [:]
            templateExercises = try applyPersistedExerciseDefaults(
                to: updatedPlan.exercises.map(\.asTemplateExerciseDetail)
            )
            currentExerciseIndex = 0
            persistSessionStateCache()
            updateLiveActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Exercise Navigation

    func nextExercise() {
        if currentExerciseIndex < templateExercises.count - 1 {
            currentExerciseIndex += 1
            persistSessionStateCache()
            updateLiveActivity()
        }
    }

    func previousExercise() {
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
            persistSessionStateCache()
            updateLiveActivity()
        }
    }

    func skipExercise() {
        nextExercise()
    }

    func addExerciseToSession(_ exercise: Exercise) {
        let templateExercise = TemplateExercise(
            templateId: currentSession?.templateId ?? UUID(),
            exerciseId: exercise.id,
            sortOrder: templateExercises.count
        )
        var detail = TemplateExerciseDetail(
            templateExercise: templateExercise,
            exercise: exercise
        )

        do {
            let persisted = try db.fetchLastLoggedValues(exerciseId: exercise.id)
            if let reps = persisted.reps {
                detail.templateExercise.targetReps = reps
            }
            if let weight = persisted.weight {
                detail.templateExercise.targetWeight = weight
            }
            if persisted.reps != nil || persisted.weight != nil {
                lastEnteredValues[exercise.id] = persisted
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        templateExercises.append(detail)
        persistSessionStateCache()
    }

    // MARK: - Set Logging

    func logSet(reps: Int?, duration: Int?, weight: Double?) async {
        guard let session = currentSession, let current = currentExercise else { return }
        guard hasSatisfiedWarmupRequirement else {
            errorMessage = "Bitte zuerst das 10-minuetige Warm-up starten oder ueberspringen."
            return
        }

        let setNumber = completedSetsForCurrentExercise.count + 1

        let set = SessionSet(
            sessionId: session.id,
            exerciseId: current.exercise.id,
            setNumber: setNumber,
            reps: reps,
            duration: duration,
            weight: weight
        )

        do {
            try db.saveSessionSet(set)
            completedSets.append(set)

            // Check for PR (only for rep-based exercises with weight)
            if let reps = reps, let weight = weight, weight > 0 {
                if let newPR = try db.checkAndSaveIfPR(
                    exerciseId: current.exercise.id,
                    weight: weight,
                    reps: reps,
                    sessionId: session.id
                ) {
                    newPRs.append(newPR)
                }
            }

            let completedForCurrentExercise = completedSetsForCurrentExercise.count
            let hasMetTargetSets = current.templateExercise.targetSets.map {
                completedForCurrentExercise >= $0
            } ?? false
            let finishedWorkout = hasMetTargetSets && isLastExercise

            if !finishedWorkout {
                startRestTimer()
            } else {
                stopRestTimer()
            }

            if hasMetTargetSets && !isLastExercise {
                nextExercise()
            } else {
                updateLiveActivity()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSet(_ set: SessionSet) async {
        do {
            try db.deleteSessionSet(set)
            completedSets.removeAll { $0.id == set.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cardio

    func addCardioSession(_ cardio: CardioSession) async {
        do {
            try db.saveCardioSession(cardio)
            cardioSessions.append(cardio)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addWarmupCardio(type: CardioType) async {
        guard let session = currentSession else { return }

        let warmup = CardioSession(
            sessionId: session.id,
            cardioType: type,
            duration: 10 * 60,
            notes: "\(warmupCardioTag) 10 minute warm-up"
        )

        await addCardioSession(warmup)
    }

    func startWarmupTimer(type: CardioType, duration: Int = 10 * 60) {
        guard currentSession != nil, !hasSatisfiedWarmupRequirement else { return }

        warmupTimer?.invalidate()
        warmupTimer = nil

        warmupCardioTypeInProgress = type
        warmupTimeRemaining = duration
        warmupTimerTotalTime = duration
        warmupTimerEndTime = Date().addingTimeInterval(Double(duration))
        isWarmupTimerActive = true
        errorMessage = nil
        persistSessionStateCache()

        warmupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard let endTime = self.warmupTimerEndTime else {
                    self.stopWarmupTimer()
                    return
                }

                let remaining = Int(ceil(endTime.timeIntervalSince(Date())))
                if remaining > 0 {
                    self.warmupTimeRemaining = remaining
                } else {
                    await self.finalizeWarmupTimerIfNeeded()
                }
            }
        }
    }

    func skipWarmup() {
        guard currentSession != nil else { return }

        hasSkippedWarmup = true
        stopWarmupTimer()
        persistSessionStateCache()
    }

    func deleteCardioSession(_ cardio: CardioSession) async {
        do {
            try db.deleteCardioSession(cardio)
            cardioSessions.removeAll { $0.id == cardio.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSessionNotes(_ sessionId: UUID, _ notes: String) async {
        do {
            if var session = try db.fetchSession(id: sessionId) {
                session.notes = notes.isEmpty ? nil : notes
                try db.saveSession(session)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Timers

    private func startWorkoutTimer() {
        stopWorkoutTimer()
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Always derive from the persisted session start time.
                if let startTime = self.currentSession?.startedAt ?? self.workoutStartTime {
                    self.workoutDuration = max(0, Int(Date().timeIntervalSince(startTime)))
                }
                // Update live activity every 5 seconds to save resources
                if self.workoutDuration % 5 == 0 && !self.isRestTimerActive {
                    self.updateLiveActivity()
                }
            }
        }
    }

    private func stopWorkoutTimer() {
        workoutTimer?.invalidate()
        workoutTimer = nil
    }

    func startRestTimer(duration: Int? = nil) {
        stopRestTimer()
        let totalTime = duration ?? defaultRestTime
        restTimeRemaining = totalTime
        restTimerTotalTime = totalTime
        restTimerEndTime = Date().addingTimeInterval(Double(totalTime))
        isRestTimerActive = true
        updateLiveActivity()

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Calculate from end time for accuracy
                if let endTime = self.restTimerEndTime {
                    let remaining = Int(ceil(endTime.timeIntervalSince(Date())))
                    if remaining > 0 {
                        self.restTimeRemaining = remaining
                        self.updateLiveActivity()
                    } else {
                        self.stopRestTimer()
                        self.triggerRestTimerEnd()
                    }
                }
            }
        }
    }

    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerActive = false
        restTimeRemaining = 0
        restTimerTotalTime = 0
        restTimerEndTime = nil
        updateLiveActivity()
    }

    func stopWarmupTimer() {
        warmupTimer?.invalidate()
        warmupTimer = nil
        isWarmupTimerActive = false
        warmupTimeRemaining = 0
        warmupTimerTotalTime = 0
        warmupTimerEndTime = nil
        warmupCardioTypeInProgress = nil
    }

    func addRestTime(_ seconds: Int) {
        if isRestTimerActive {
            restTimeRemaining += seconds
            // Don't let it go below 1 second
            if restTimeRemaining < 1 {
                restTimeRemaining = 1
            }
            // Update total time if we're adding time (for progress calculation)
            if seconds > 0 {
                restTimerTotalTime += seconds
            }
            // Update end time
            restTimerEndTime = Date().addingTimeInterval(Double(restTimeRemaining))
            updateLiveActivity()
        }
    }

    private func triggerRestTimerEnd() {
#if canImport(UIKit)
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
#endif
    }

    // MARK: - Live Activity

    private func startLiveActivity(templateName: String) {
#if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let exerciseName = currentExercise?.exercise.name ?? "Ready"
        let setProgress = currentExercise != nil ? "Set 1/\(currentExercise?.templateExercise.targetSets ?? 0)" : ""

        let attributes = WorkoutActivityAttributes(
            templateName: templateName,
            startedAt: Date()
        )

        let state = WorkoutActivityAttributes.ContentState(
            workoutDuration: workoutDuration,
            isResting: false,
            restTimeRemaining: 0,
            currentExercise: exerciseName,
            setProgress: setProgress,
            totalSetsCompleted: 0
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
#endif
    }

    private func updateLiveActivity() {
#if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let exerciseName = currentExercise?.exercise.name ?? "Done"
        let completedForCurrent = completedSetsForCurrentExercise.count
        let targetSets = currentExercise?.templateExercise.targetSets ?? 0
        let setProgress = currentExercise != nil ? "Set \(completedForCurrent + 1)/\(targetSets)" : ""

        let state = WorkoutActivityAttributes.ContentState(
            workoutDuration: workoutDuration,
            isResting: isRestTimerActive,
            restTimeRemaining: restTimeRemaining,
            currentExercise: exerciseName,
            setProgress: setProgress,
            totalSetsCompleted: completedSets.count
        )

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
        }
#endif
    }

    private func endLiveActivity() {
#if canImport(ActivityKit)
        guard let activity = currentActivity else { return }

        let finalState = WorkoutActivityAttributes.ContentState(
            workoutDuration: workoutDuration,
            isResting: false,
            restTimeRemaining: 0,
            currentExercise: "Workout Complete",
            setProgress: "",
            totalSetsCompleted: completedSets.count
        )

        Task {
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .after(.now + 60))
        }

        currentActivity = nil
#endif
    }

    // MARK: - Helpers

    var formattedWorkoutDuration: String {
        formatDuration(workoutDuration)
    }

    var formattedRestTime: String {
        formatDuration(restTimeRemaining)
    }

    var formattedWarmupTime: String {
        formatDuration(warmupTimeRemaining)
    }

    private func applyPersistedExerciseDefaults(
        to exercises: [TemplateExerciseDetail]
    ) throws -> [TemplateExerciseDetail] {
        var updated: [TemplateExerciseDetail] = []

        for var detail in exercises {
            let persisted = try db.fetchLastLoggedValues(exerciseId: detail.exercise.id)

            if let reps = persisted.reps {
                detail.templateExercise.targetReps = reps
            }

            if let weight = persisted.weight {
                detail.templateExercise.targetWeight = weight
            }

            if persisted.reps != nil || persisted.weight != nil {
                lastEnteredValues[detail.exercise.id] = persisted
            }

            updated.append(detail)
        }

        return updated
    }

    // MARK: - Active Session Recovery

    private func restoreActiveSessionIfNeeded() async {
        do {
            guard let activeSession = try db.fetchActiveSession() else { return }
            currentSession = activeSession
            if let dayPlanId = activeSession.dayPlanId {
                currentDayPlan = try db.fetchWorkoutDayPlan(id: dayPlanId)
            } else {
                currentDayPlan = nil
            }
            isWorkoutActive = true

            workoutStartTime = activeSession.startedAt
            workoutDuration = max(0, Int(Date().timeIntervalSince(activeSession.startedAt)))
            sessionNotes = activeSession.notes ?? ""
            newPRs = []
            errorMessage = nil

            if let sessionDetails = try db.fetchSessionWithDetails(id: activeSession.id) {
                completedSets = sessionDetails.sets.map { $0.sessionSet }
                cardioSessions = sessionDetails.cardioSessions
            } else {
                completedSets = []
                cardioSessions = []
            }

            hasSkippedWarmup = loadCachedWarmupSkip(sessionId: activeSession.id)
            if hasLoggedWarmup {
                hasSkippedWarmup = false
                stopWarmupTimer()
            } else if hasSkippedWarmup {
                stopWarmupTimer()
            } else {
                restoreWarmupTimer(sessionId: activeSession.id)
                if isWarmupTimerActive, warmupTimeRemaining == 0 {
                    await finalizeWarmupTimerIfNeeded()
                }
            }

            lastEnteredValues = [:]
            if let cachedExercises = loadCachedTemplateExercises(sessionId: activeSession.id), !cachedExercises.isEmpty {
                templateExercises = cachedExercises
            } else if let currentDayPlan {
                templateExercises = try applyPersistedExerciseDefaults(
                    to: currentDayPlan.exercises.map(\.asTemplateExerciseDetail)
                )
            } else if let templateId = activeSession.templateId {
                templateExercises = try applyPersistedExerciseDefaults(
                    to: db.fetchTemplateExercises(templateId: templateId)
                )
            } else {
                templateExercises = []
            }

            for set in completedSets.sorted(by: { $0.completedAt < $1.completedAt }) {
                if set.reps != nil || set.weight != nil {
                    lastEnteredValues[set.exerciseId] = (set.reps, set.weight)
                }
            }

            currentExerciseIndex = restoredExerciseIndex(sessionId: activeSession.id)
            startWorkoutTimer()
            ensureLiveActivityForCurrentSession()
            updateLiveActivity()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureLiveActivityForCurrentSession() {
#if canImport(ActivityKit)
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            currentActivity = existing
            return
        }

        let templateName: String
        if let templateId = currentSession?.templateId,
           let template = try? db.fetchTemplate(id: templateId) {
            templateName = template.name
        } else {
            templateName = "Free Workout"
        }

        startLiveActivity(templateName: templateName)
#endif
    }

    private func restoredExerciseIndex(sessionId: UUID) -> Int {
        let cachedIndex = UserDefaults.standard.integer(forKey: sessionIndexCacheKey(sessionId: sessionId))
        if templateExercises.isEmpty {
            return 0
        }

        if cachedIndex >= 0 && cachedIndex < templateExercises.count {
            return cachedIndex
        }

        for (index, detail) in templateExercises.enumerated() {
            guard let targetSets = detail.templateExercise.targetSets else { continue }
            let completedForExercise = completedSets.filter { $0.exerciseId == detail.exercise.id }.count
            if completedForExercise < targetSets {
                return index
            }
        }

        return max(0, min(templateExercises.count - 1, cachedIndex))
    }

    // MARK: - Session State Cache

    private func sessionExerciseCacheKey(sessionId: UUID) -> String {
        "\(sessionExerciseCachePrefix)\(sessionId.uuidString)"
    }

    private func sessionIndexCacheKey(sessionId: UUID) -> String {
        "\(sessionIndexCachePrefix)\(sessionId.uuidString)"
    }

    private func sessionWarmupSkipCacheKey(sessionId: UUID) -> String {
        "\(sessionWarmupSkipCachePrefix)\(sessionId.uuidString)"
    }

    private func sessionWarmupEndCacheKey(sessionId: UUID) -> String {
        "\(sessionWarmupEndCachePrefix)\(sessionId.uuidString)"
    }

    private func sessionWarmupTotalCacheKey(sessionId: UUID) -> String {
        "\(sessionWarmupTotalCachePrefix)\(sessionId.uuidString)"
    }

    private func sessionWarmupTypeCacheKey(sessionId: UUID) -> String {
        "\(sessionWarmupTypeCachePrefix)\(sessionId.uuidString)"
    }

    private func persistSessionStateCache() {
        guard let session = currentSession else { return }

        do {
            let data = try JSONEncoder().encode(templateExercises)
            UserDefaults.standard.set(data, forKey: sessionExerciseCacheKey(sessionId: session.id))
            UserDefaults.standard.set(currentExerciseIndex, forKey: sessionIndexCacheKey(sessionId: session.id))
            UserDefaults.standard.set(hasSkippedWarmup, forKey: sessionWarmupSkipCacheKey(sessionId: session.id))

            if isWarmupTimerActive,
               let warmupTimerEndTime,
               let warmupCardioTypeInProgress {
                UserDefaults.standard.set(warmupTimerEndTime.timeIntervalSince1970, forKey: sessionWarmupEndCacheKey(sessionId: session.id))
                UserDefaults.standard.set(warmupTimerTotalTime, forKey: sessionWarmupTotalCacheKey(sessionId: session.id))
                UserDefaults.standard.set(warmupCardioTypeInProgress.rawValue, forKey: sessionWarmupTypeCacheKey(sessionId: session.id))
            } else {
                UserDefaults.standard.removeObject(forKey: sessionWarmupEndCacheKey(sessionId: session.id))
                UserDefaults.standard.removeObject(forKey: sessionWarmupTotalCacheKey(sessionId: session.id))
                UserDefaults.standard.removeObject(forKey: sessionWarmupTypeCacheKey(sessionId: session.id))
            }
        } catch {
            // Non-fatal: session still works, only restoration quality degrades.
            print("Failed to persist workout session cache: \(error)")
        }
    }

    private func loadCachedTemplateExercises(sessionId: UUID) -> [TemplateExerciseDetail]? {
        guard let data = UserDefaults.standard.data(forKey: sessionExerciseCacheKey(sessionId: sessionId)) else {
            return nil
        }
        return try? JSONDecoder().decode([TemplateExerciseDetail].self, from: data)
    }

    private func clearSessionStateCache(sessionId: UUID) {
        UserDefaults.standard.removeObject(forKey: sessionExerciseCacheKey(sessionId: sessionId))
        UserDefaults.standard.removeObject(forKey: sessionIndexCacheKey(sessionId: sessionId))
        UserDefaults.standard.removeObject(forKey: sessionWarmupSkipCacheKey(sessionId: sessionId))
        UserDefaults.standard.removeObject(forKey: sessionWarmupEndCacheKey(sessionId: sessionId))
        UserDefaults.standard.removeObject(forKey: sessionWarmupTotalCacheKey(sessionId: sessionId))
        UserDefaults.standard.removeObject(forKey: sessionWarmupTypeCacheKey(sessionId: sessionId))
    }

    private func finalizeWarmupTimerIfNeeded() async {
        guard isWarmupTimerActive else { return }

        let warmupType = warmupCardioTypeInProgress ?? .treadmill
        stopWarmupTimer()
        await addWarmupCardio(type: warmupType)
        persistSessionStateCache()
    }

    private func restoreWarmupTimer(sessionId: UUID) {
        stopWarmupTimer()

        guard let rawType = UserDefaults.standard.string(forKey: sessionWarmupTypeCacheKey(sessionId: sessionId)),
              let cardioType = CardioType(rawValue: rawType) else {
            return
        }

        let endInterval = UserDefaults.standard.double(forKey: sessionWarmupEndCacheKey(sessionId: sessionId))
        let totalTime = UserDefaults.standard.integer(forKey: sessionWarmupTotalCacheKey(sessionId: sessionId))
        guard endInterval > 0, totalTime > 0 else { return }

        warmupCardioTypeInProgress = cardioType
        warmupTimerTotalTime = totalTime
        warmupTimerEndTime = Date(timeIntervalSince1970: endInterval)

        let remaining = Int(ceil(warmupTimerEndTime?.timeIntervalSince(Date()) ?? 0))
        if remaining <= 0 {
            isWarmupTimerActive = true
            warmupTimeRemaining = 0
            return
        }

        warmupTimeRemaining = remaining
        isWarmupTimerActive = true
        startWarmupTimer(type: cardioType, duration: remaining)
        warmupTimerTotalTime = totalTime
        warmupTimerEndTime = Date(timeIntervalSince1970: endInterval)
        persistSessionStateCache()
    }

    private func loadCachedWarmupSkip(sessionId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: sessionWarmupSkipCacheKey(sessionId: sessionId))
    }

    private func resetWarmupState() {
        hasSkippedWarmup = false
        stopWarmupTimer()
    }

    private func snapshots(from dayPlan: WorkoutDayPlanWithExercises) -> [WorkoutPlanExerciseSnapshot] {
        dayPlan.exercises.map {
            WorkoutPlanExerciseSnapshot(
                exercise: $0.exercise,
                sortOrder: $0.planExercise.sortOrder,
                isAnchor: $0.planExercise.isAnchor
            )
        }
    }

    // MARK: - Template Variation

    private func buildVariedTemplateExercises(
        templateId: UUID,
        baseExercises: [TemplateExerciseDetail]
    ) throws -> [TemplateExerciseDetail] {
        guard !baseExercises.isEmpty else { return [] }
        guard baseExercises.count > 1 else { return reorderForTrainingFlow(baseExercises) }

        let allExercises = try db.fetchAllExercises()
        let slotCandidates = buildSlotCandidates(baseExercises: baseExercises, allExercises: allExercises)
        let variantA = primaryVariant(baseExercises: baseExercises)
        let variantB = secondaryVariant(
            baseExercises: baseExercises,
            slotCandidates: slotCandidates,
            primaryVariant: variantA
        )

        let signatureA = signature(for: variantA)
        let signatureB = signature(for: variantB)

        // If no meaningful alternative is possible, keep the best-ordered baseline.
        if signatureA == signatureB {
            saveLastUsedVariantIndex(0, categoryKey: templateCategoryKey(templateId: templateId))
            return reorderForTrainingFlow(variantA)
        }

        let categoryKey = templateCategoryKey(templateId: templateId)
        let lastVariant = lastUsedVariantIndex(categoryKey: categoryKey)
        let nextVariant = lastVariant == 0 ? 1 : 0
        saveLastUsedVariantIndex(nextVariant, categoryKey: categoryKey)

        let selected = nextVariant == 0 ? variantA : variantB
        return reorderForTrainingFlow(selected)
    }

    private func buildSlotCandidates(
        baseExercises: [TemplateExerciseDetail],
        allExercises: [Exercise]
    ) -> [[Exercise]] {
        baseExercises.map { detail in
            let baseMuscles = normalizedMuscles(detail.exercise.muscleGroups)

            return allExercises
                .filter { candidate in
                    guard candidate.exerciseType == detail.exercise.exerciseType else { return false }

                    if candidate.id == detail.exercise.id {
                        return true
                    }

                    let candidateMuscles = normalizedMuscles(candidate.muscleGroups)
                    guard !baseMuscles.isEmpty, !candidateMuscles.isEmpty else { return false }

                    return !baseMuscles.isDisjoint(with: candidateMuscles)
                }
                .sorted { $0.name < $1.name }
        }
    }

    private func primaryVariant(
        baseExercises: [TemplateExerciseDetail]
    ) -> [TemplateExerciseDetail] {
        baseExercises.enumerated().map { index, base in
            detailWithExercise(base: base, exercise: base.exercise, sortOrder: index)
        }
    }

    private func secondaryVariant(
        baseExercises: [TemplateExerciseDetail],
        slotCandidates: [[Exercise]],
        primaryVariant: [TemplateExerciseDetail]
    ) -> [TemplateExerciseDetail] {
        guard !baseExercises.isEmpty else { return [] }

        var varied: [TemplateExerciseDetail] = []
        var usedExerciseIDs = Set<UUID>()

        for index in baseExercises.indices {
            let base = baseExercises[index]
            let primaryExercise = primaryVariant[index].exercise

            let alternatives = slotCandidates[index]
                .filter { candidate in
                    guard candidate.exerciseType == base.exercise.exerciseType else { return false }
                    guard !usedExerciseIDs.contains(candidate.id) else { return false }
                    return candidate.id != primaryExercise.id
                }
                .sorted { lhs, rhs in
                    let leftRank = trainingFlowRank(for: lhs)
                    let rightRank = trainingFlowRank(for: rhs)
                    if leftRank.muscleRank != rightRank.muscleRank {
                        return leftRank.muscleRank < rightRank.muscleRank
                    }
                    if leftRank.isolationRank != rightRank.isolationRank {
                        return leftRank.isolationRank < rightRank.isolationRank
                    }
                    return lhs.name < rhs.name
                }

            let chosenExercise = alternatives.first ?? primaryExercise
            varied.append(detailWithExercise(base: base, exercise: chosenExercise, sortOrder: index))
            usedExerciseIDs.insert(chosenExercise.id)
        }

        return varied
    }

    private func reorderForTrainingFlow(
        _ exercises: [TemplateExerciseDetail]
    ) -> [TemplateExerciseDetail] {
        let sorted = exercises.sorted { lhs, rhs in
            let leftRank = trainingFlowRank(for: lhs.exercise)
            let rightRank = trainingFlowRank(for: rhs.exercise)

            if leftRank.muscleRank != rightRank.muscleRank {
                return leftRank.muscleRank < rightRank.muscleRank
            }

            if leftRank.isolationRank != rightRank.isolationRank {
                return leftRank.isolationRank < rightRank.isolationRank
            }

            return lhs.templateExercise.sortOrder < rhs.templateExercise.sortOrder
        }

        return sorted.enumerated().map { index, detail in
            var templateExercise = detail.templateExercise
            templateExercise.sortOrder = index
            return TemplateExerciseDetail(templateExercise: templateExercise, exercise: detail.exercise)
        }
    }

    private func trainingFlowRank(for exercise: Exercise) -> (muscleRank: Int, isolationRank: Int) {
        let muscles = normalizedMuscles(exercise.muscleGroups)

        let largeGroups: Set<String> = ["chest", "back", "quadriceps", "hamstrings", "glutes"]
        let mediumGroups: Set<String> = ["shoulders", "core"]
        let smallGroups: Set<String> = ["biceps", "triceps", "forearms", "calves"]

        let muscleRank: Int
        if !muscles.isDisjoint(with: largeGroups) {
            muscleRank = 0
        } else if !muscles.isDisjoint(with: mediumGroups) {
            muscleRank = 1
        } else if !muscles.isDisjoint(with: smallGroups) {
            muscleRank = 2
        } else {
            muscleRank = 1
        }

        let isolationRank = isLikelyIsolation(exercise: exercise, normalizedMuscles: muscles) ? 1 : 0
        return (muscleRank, isolationRank)
    }

    private func isLikelyIsolation(exercise: Exercise, normalizedMuscles: Set<String>) -> Bool {
        let compoundKeywords = [
            "press", "bench", "row", "rudern", "squat", "kniebeuge",
            "deadlift", "kreuzheben", "lunge", "dip", "pull", "latzug", "beinpresse"
        ]

        let isolationKeywords = [
            "curl", "pushdown", "extension", "kickback", "fly", "heben", "raise", "crunch"
        ]

        let name = exercise.name.lowercased()
        if compoundKeywords.contains(where: { name.contains($0) }) {
            return false
        }

        if isolationKeywords.contains(where: { name.contains($0) }) {
            return true
        }

        let smallGroups: Set<String> = ["biceps", "triceps", "forearms", "calves"]
        return normalizedMuscles.count <= 1 || !normalizedMuscles.isDisjoint(with: smallGroups)
    }

    private func detailWithExercise(
        base: TemplateExerciseDetail,
        exercise: Exercise,
        sortOrder: Int
    ) -> TemplateExerciseDetail {
        var templateExercise = base.templateExercise
        templateExercise.exerciseId = exercise.id
        templateExercise.sortOrder = sortOrder
        return TemplateExerciseDetail(templateExercise: templateExercise, exercise: exercise)
    }

    private func templateCategoryKey(templateId: UUID) -> String {
        guard let template = try? db.fetchTemplate(id: templateId) else {
            return "template-\(templateId.uuidString)"
        }

        let normalizedName = template.name.lowercased()

        if normalizedName.contains("push") || normalizedName.contains("brust") {
            return "push"
        }
        if normalizedName.contains("pull") || normalizedName.contains("rücken") {
            return "pull"
        }
        if normalizedName.contains("leg") || normalizedName.contains("bein") {
            return "legs"
        }
        if normalizedName.contains("schulter") || normalizedName.contains("shoulder") {
            return "shoulders"
        }

        return "template-\(templateId.uuidString)"
    }

    private func lastUsedVariantIndex(categoryKey: String) -> Int? {
        let key = categoryVariantKey(categoryKey: categoryKey)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    private func saveLastUsedVariantIndex(_ index: Int, categoryKey: String) {
        UserDefaults.standard.set(index, forKey: categoryVariantKey(categoryKey: categoryKey))
    }

    private func categoryVariantKey(categoryKey: String) -> String {
        let safeCategory = categoryKey.replacingOccurrences(of: " ", with: "-")
        return "\(categoryVariantKeyPrefix)\(safeCategory)"
    }

    private func normalizedMuscles(_ muscles: [String]) -> Set<String> {
        Set(muscles.map { normalizeMuscleName($0) }.filter { !$0.isEmpty })
    }

    private func dayPlanDrafts(from dayPlan: WorkoutDayPlanWithExercises) -> [WorkoutPlanExerciseDraft] {
        dayPlan.exercises.map { detail in
            WorkoutPlanExerciseDraft(
                exercise: detail.exercise,
                sortOrder: detail.planExercise.sortOrder,
                targetSets: detail.planExercise.targetSets,
                targetReps: detail.planExercise.targetReps,
                targetDuration: detail.planExercise.targetDuration,
                targetWeight: detail.planExercise.targetWeight,
                isAnchor: detail.planExercise.isAnchor
            )
        }
    }

    private func rotationSeed(
        completedSessionCount: Int,
        style: WorkoutRotationStyle
    ) -> Int {
        completedSessionCount / max(1, style.cadenceSessions)
    }

    private func normalizeMuscleName(_ muscle: String) -> String {
        let normalized = muscle
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "front delts", "rear delts", "shoulders", "vordere schulter", "hintere schulter":
            return "shoulders"
        case "upper back", "lower back", "back", "rücken":
            return "back"
        case "abs", "core", "bauch":
            return "core"
        case "chest", "brust":
            return "chest"
        case "triceps", "trizeps":
            return "triceps"
        case "biceps", "bizeps":
            return "biceps"
        case "forearms", "unterarme":
            return "forearms"
        case "glutes", "gesäß":
            return "glutes"
        case "hamstrings", "beinbeuger":
            return "hamstrings"
        case "quads", "quadriceps", "vorderer oberschenkel":
            return "quadriceps"
        case "calves", "waden":
            return "calves"
        default:
            return normalized
        }
    }

    private func signature(for exercises: [TemplateExerciseDetail]) -> String {
        exercises.map { $0.exercise.id.uuidString }.joined(separator: "|")
    }
}
