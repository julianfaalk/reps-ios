import Foundation
import SwiftUI
import Combine
import ActivityKit

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var currentExerciseIndex: Int = 0
    @Published var templateExercises: [TemplateExerciseDetail] = []
    @Published var completedSets: [SessionSet] = []
    @Published var cardioSessions: [CardioSession] = []

    @Published var workoutDuration: Int = 0
    @Published var restTimeRemaining: Int = 0
    @Published var restTimerTotalTime: Int = 0
    @Published var isRestTimerActive: Bool = false
    @Published var isWorkoutActive: Bool = false

    @Published var sessionNotes: String = ""
    @Published var newPRs: [PersonalRecord] = []

    @Published var errorMessage: String?

    // Track last entered values per exercise during this session
    private var lastEnteredValues: [UUID: (reps: Int?, weight: Double?)] = [:]

    private let db = DatabaseService.shared
    private var workoutTimer: Timer?
    private var restTimer: Timer?
    private var defaultRestTime: Int = 90
    private var currentActivity: Activity<WorkoutActivityAttributes>?

    // Timestamps for background persistence
    private var workoutStartTime: Date?
    private var workoutPausedDuration: Int = 0
    private var restTimerEndTime: Date?

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

    init() {
        loadSettings()
        setupBackgroundObservers()
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
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillResignActive()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidBecomeActive()
        }
    }

    private func handleAppWillResignActive() {
        // Store current state for when we come back
        // Timers will be recalculated from timestamps when we return
    }

    private func handleAppDidBecomeActive() {
        // Recalculate workout duration from start time
        if isWorkoutActive, let startTime = workoutStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            workoutDuration = elapsed + workoutPausedDuration
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
        let session = WorkoutSession(templateId: templateId)

        do {
            try db.saveSession(session)
            currentSession = session

            var templateName = "Free Workout"
            if let templateId = templateId {
                templateExercises = try db.fetchTemplateExercises(templateId: templateId)
                if let template = try? db.fetchTemplate(id: templateId) {
                    templateName = template.name
                }
            }

            currentExerciseIndex = 0
            completedSets = []
            cardioSessions = []
            workoutDuration = 0
            workoutPausedDuration = 0
            workoutStartTime = Date()
            sessionNotes = ""
            newPRs = []
            lastEnteredValues = [:]
            isWorkoutActive = true

            startWorkoutTimer()
            startLiveActivity(templateName: templateName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAdHocSession() async {
        await startSession(templateId: nil)
    }

    func completeSession() async -> SessionWithDetails? {
        guard var session = currentSession else { return nil }

        stopWorkoutTimer()
        stopRestTimer()
        endLiveActivity()

        session.completedAt = Date()
        session.duration = workoutDuration
        session.notes = sessionNotes.isEmpty ? nil : sessionNotes

        do {
            try db.saveSession(session)
            currentSession = nil
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
        endLiveActivity()

        if let session = currentSession {
            try? db.deleteSession(session)
        }

        currentSession = nil
        isWorkoutActive = false
        templateExercises = []
        completedSets = []
        cardioSessions = []
    }

    // MARK: - Exercise Navigation

    func nextExercise() {
        if currentExerciseIndex < templateExercises.count - 1 {
            currentExerciseIndex += 1
            updateLiveActivity()
        }
    }

    func previousExercise() {
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
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
        templateExercises.append(TemplateExerciseDetail(
            templateExercise: templateExercise,
            exercise: exercise
        ))
    }

    // MARK: - Set Logging

    func logSet(reps: Int?, duration: Int?, weight: Double?) async {
        guard let session = currentSession, let current = currentExercise else { return }

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

            // Start rest timer
            startRestTimer()

            // Auto-advance if all target sets are done
            if let targetSets = current.templateExercise.targetSets,
               completedSetsForCurrentExercise.count >= targetSets,
               !isLastExercise {
                // Don't auto-advance, let user decide
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
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Calculate from start time for accuracy (handles background)
                if let startTime = self.workoutStartTime {
                    self.workoutDuration = Int(Date().timeIntervalSince(startTime)) + self.workoutPausedDuration
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
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Live Activity

    private func startLiveActivity(templateName: String) {
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
    }

    private func updateLiveActivity() {
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
    }

    private func endLiveActivity() {
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
    }

    // MARK: - Helpers

    var formattedWorkoutDuration: String {
        formatDuration(workoutDuration)
    }

    var formattedRestTime: String {
        formatDuration(restTimeRemaining)
    }
}
