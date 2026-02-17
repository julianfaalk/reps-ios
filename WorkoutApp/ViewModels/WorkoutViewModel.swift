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
    private let variationHistoryKeyPrefix = "workout.variation.history."
    private let variationHistoryDepth = 3
    private let variationRetryCount = 8

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
                let baseTemplateExercises = try db.fetchTemplateExercises(templateId: templateId)
                templateExercises = try buildVariedTemplateExercises(
                    templateId: templateId,
                    baseExercises: baseTemplateExercises
                )
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

    // MARK: - Template Variation

    private func buildVariedTemplateExercises(
        templateId: UUID,
        baseExercises: [TemplateExerciseDetail]
    ) throws -> [TemplateExerciseDetail] {
        guard baseExercises.count > 1 else { return baseExercises }

        let allExercises = try db.fetchAllExercises()
        let recentSignatures = loadVariationHistory(templateId: templateId)
        let blockedSignatures = Array(recentSignatures.prefix(2))
        let recentUsagePenalty = recentExercisePenalty(templateId: templateId)
        let slotCandidates = buildSlotCandidates(baseExercises: baseExercises, allExercises: allExercises)

        var candidate = baseExercises
        var selectedSignature = signature(for: candidate)

        for _ in 0..<variationRetryCount {
            let next = generateVariationCandidate(
                baseExercises: baseExercises,
                slotCandidates: slotCandidates,
                recentUsagePenalty: recentUsagePenalty
            )
            let nextSignature = signature(for: next)
            candidate = next
            selectedSignature = nextSignature

            if !blockedSignatures.contains(nextSignature) {
                break
            }
        }

        if blockedSignatures.contains(selectedSignature) {
            candidate = forceSingleSlotChange(
                candidate: candidate,
                baseExercises: baseExercises,
                slotCandidates: slotCandidates,
                blockedSignatures: blockedSignatures
            )
            selectedSignature = signature(for: candidate)
        }

        saveVariationSignature(selectedSignature, templateId: templateId)
        return candidate
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

    private func generateVariationCandidate(
        baseExercises: [TemplateExerciseDetail],
        slotCandidates: [[Exercise]],
        recentUsagePenalty: [UUID: Double]
    ) -> [TemplateExerciseDetail] {
        var result: [TemplateExerciseDetail] = []
        var usedExerciseIDs = Set<UUID>()

        for index in baseExercises.indices {
            let base = baseExercises[index]
            let isAnchorSlot = index == 0

            if isAnchorSlot {
                result.append(detailWithExercise(base: base, exercise: base.exercise, sortOrder: index))
                usedExerciseIDs.insert(base.exercise.id)
                continue
            }

            let candidates = slotCandidates[index]
            if candidates.isEmpty {
                result.append(detailWithExercise(base: base, exercise: base.exercise, sortOrder: index))
                usedExerciseIDs.insert(base.exercise.id)
                continue
            }

            let ranked = candidates
                .map { exercise -> (Exercise, Double) in
                    var score = Double.random(in: 0...0.6)

                    if usedExerciseIDs.contains(exercise.id) {
                        score += 100
                    }

                    // Keep some continuity while still preferring variation.
                    if exercise.id == base.exercise.id {
                        score += 1.2
                    }

                    score += recentUsagePenalty[exercise.id] ?? 0
                    return (exercise, score)
                }
                .sorted { $0.1 < $1.1 }

            let topCount = min(3, ranked.count)
            let picked = topCount > 1
                ? ranked[Int.random(in: 0..<topCount)].0
                : ranked[0].0

            result.append(detailWithExercise(base: base, exercise: picked, sortOrder: index))
            usedExerciseIDs.insert(picked.id)
        }

        return result
    }

    private func forceSingleSlotChange(
        candidate: [TemplateExerciseDetail],
        baseExercises: [TemplateExerciseDetail],
        slotCandidates: [[Exercise]],
        blockedSignatures: [String]
    ) -> [TemplateExerciseDetail] {
        guard candidate.count > 1 else { return candidate }

        var updated = candidate
        var used = Set(updated.map { $0.exercise.id })

        for index in 1..<updated.count {
            let currentExerciseId = updated[index].exercise.id
            for alternative in slotCandidates[index] {
                guard alternative.id != currentExerciseId else { continue }
                guard !used.contains(alternative.id) else { continue }

                used.remove(currentExerciseId)
                used.insert(alternative.id)
                updated[index] = detailWithExercise(
                    base: baseExercises[index],
                    exercise: alternative,
                    sortOrder: index
                )

                let newSignature = signature(for: updated)
                if !blockedSignatures.contains(newSignature) {
                    return updated
                }

                used.remove(alternative.id)
                used.insert(currentExerciseId)
                updated[index] = candidate[index]
            }
        }

        return candidate
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

    private func recentExercisePenalty(templateId: UUID) -> [UUID: Double] {
        var penalty: [UUID: Double] = [:]

        let recentSignatures = loadVariationHistory(templateId: templateId)
        for (index, signature) in recentSignatures.prefix(2).enumerated() {
            let score = index == 0 ? 3.0 : 1.5
            for exerciseId in parseSignature(signature) {
                penalty[exerciseId, default: 0] += score
            }
        }

        let recentSessionExercises = fetchRecentTemplateExerciseUsage(templateId: templateId, limit: 2)
        for (index, exerciseIds) in recentSessionExercises.enumerated() {
            let score = index == 0 ? 2.0 : 1.0
            for exerciseId in exerciseIds {
                penalty[exerciseId, default: 0] += score
            }
        }

        return penalty
    }

    private func fetchRecentTemplateExerciseUsage(templateId: UUID, limit: Int) -> [[UUID]] {
        do {
            let sessions = try db.fetchRecentSessions(limit: 30)
                .filter { $0.session.templateId == templateId }
                .prefix(limit)

            return sessions.map { session in
                Array(Set(session.sets.map { $0.exercise.id }))
            }
        } catch {
            return []
        }
    }

    private func normalizedMuscles(_ muscles: [String]) -> Set<String> {
        Set(muscles.map { normalizeMuscleName($0) }.filter { !$0.isEmpty })
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

    private func parseSignature(_ signature: String) -> [UUID] {
        signature
            .split(separator: "|")
            .compactMap { UUID(uuidString: String($0)) }
    }

    private func variationHistoryKey(templateId: UUID) -> String {
        "\(variationHistoryKeyPrefix)\(templateId.uuidString)"
    }

    private func loadVariationHistory(templateId: UUID) -> [String] {
        UserDefaults.standard.stringArray(forKey: variationHistoryKey(templateId: templateId)) ?? []
    }

    private func saveVariationSignature(_ signature: String, templateId: UUID) {
        var history = loadVariationHistory(templateId: templateId)
        history.removeAll { $0 == signature }
        history.insert(signature, at: 0)
        history = Array(history.prefix(variationHistoryDepth))
        UserDefaults.standard.set(history, forKey: variationHistoryKey(templateId: templateId))
    }
}
