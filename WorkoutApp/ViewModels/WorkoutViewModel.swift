import Foundation
import SwiftUI
import Combine

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var currentExerciseIndex: Int = 0
    @Published var templateExercises: [TemplateExerciseDetail] = []
    @Published var completedSets: [SessionSet] = []
    @Published var cardioSessions: [CardioSession] = []

    @Published var workoutDuration: Int = 0
    @Published var restTimeRemaining: Int = 0
    @Published var isRestTimerActive: Bool = false
    @Published var isWorkoutActive: Bool = false

    @Published var sessionNotes: String = ""
    @Published var newPRs: [PersonalRecord] = []

    @Published var errorMessage: String?

    private let db = DatabaseService.shared
    private var workoutTimer: Timer?
    private var restTimer: Timer?
    private var defaultRestTime: Int = 90

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
    }

    private func loadSettings() {
        do {
            let settings = try db.fetchSettings()
            defaultRestTime = settings.defaultRestTime
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session Management

    func startSession(templateId: UUID?) async {
        let session = WorkoutSession(templateId: templateId)

        do {
            try db.saveSession(session)
            currentSession = session

            if let templateId = templateId {
                templateExercises = try db.fetchTemplateExercises(templateId: templateId)
            }

            currentExerciseIndex = 0
            completedSets = []
            cardioSessions = []
            workoutDuration = 0
            sessionNotes = ""
            newPRs = []
            isWorkoutActive = true

            startWorkoutTimer()
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
        }
    }

    func previousExercise() {
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
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

    // MARK: - Timers

    private func startWorkoutTimer() {
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.workoutDuration += 1
            }
        }
    }

    private func stopWorkoutTimer() {
        workoutTimer?.invalidate()
        workoutTimer = nil
    }

    func startRestTimer(duration: Int? = nil) {
        stopRestTimer()
        restTimeRemaining = duration ?? defaultRestTime
        isRestTimerActive = true

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.restTimeRemaining > 0 {
                    self.restTimeRemaining -= 1
                } else {
                    self.stopRestTimer()
                    // Trigger haptic/sound notification
                    self.triggerRestTimerEnd()
                }
            }
        }
    }

    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerActive = false
        restTimeRemaining = 0
    }

    func addRestTime(_ seconds: Int) {
        if isRestTimerActive {
            restTimeRemaining += seconds
        }
    }

    private func triggerRestTimerEnd() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Helpers

    var formattedWorkoutDuration: String {
        formatDuration(workoutDuration)
    }

    var formattedRestTime: String {
        formatDuration(restTimeRemaining)
    }
}
