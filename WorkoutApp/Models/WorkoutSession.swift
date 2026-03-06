import Foundation
import GRDB

struct WorkoutSession: Identifiable, Codable, Hashable {
    var id: UUID
    var templateId: UUID?
    var dayPlanId: UUID?
    var startedAt: Date
    var completedAt: Date?
    var duration: Int?
    var notes: String?

    init(
        id: UUID = UUID(),
        templateId: UUID? = nil,
        dayPlanId: UUID? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        duration: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.dayPlanId = dayPlanId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.duration = duration
        self.notes = notes
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        return formatDuration(duration)
    }
}

// MARK: - GRDB Support
extension WorkoutSession: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_sessions"

    enum Columns: String, ColumnExpression {
        case id, templateId = "template_id", dayPlanId = "day_plan_id", startedAt = "started_at"
        case completedAt = "completed_at", duration, notes
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        templateId = row[Columns.templateId]
        dayPlanId = row[Columns.dayPlanId]
        startedAt = try row[Columns.startedAt]
        completedAt = row[Columns.completedAt]
        duration = row[Columns.duration]
        notes = row[Columns.notes]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.templateId] = templateId
        container[Columns.dayPlanId] = dayPlanId
        container[Columns.startedAt] = startedAt
        container[Columns.completedAt] = completedAt
        container[Columns.duration] = duration
        container[Columns.notes] = notes
    }
}

struct SessionSet: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var exerciseId: UUID
    var setNumber: Int
    var reps: Int?
    var duration: Int?
    var weight: Double?
    var completedAt: Date

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        exerciseId: UUID,
        setNumber: Int,
        reps: Int? = nil,
        duration: Int? = nil,
        weight: Double? = nil,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.reps = reps
        self.duration = duration
        self.weight = weight
        self.completedAt = completedAt
    }

    var formattedWeight: String {
        guard let weight = weight else { return "-" }
        return weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weight)) kg"
            : String(format: "%.1f kg", weight)
    }

    var formattedDuration: String {
        guard let duration = duration else { return "-" }
        return formatDuration(duration)
    }
}

// MARK: - GRDB Support
extension SessionSet: FetchableRecord, PersistableRecord {
    static let databaseTableName = "session_sets"

    enum Columns: String, ColumnExpression {
        case id, sessionId = "session_id", exerciseId = "exercise_id"
        case setNumber = "set_number", reps, duration, weight
        case completedAt = "completed_at"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        sessionId = try row[Columns.sessionId]
        exerciseId = try row[Columns.exerciseId]
        setNumber = try row[Columns.setNumber]
        reps = row[Columns.reps]
        duration = row[Columns.duration]
        weight = row[Columns.weight]
        completedAt = try row[Columns.completedAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.sessionId] = sessionId
        container[Columns.exerciseId] = exerciseId
        container[Columns.setNumber] = setNumber
        container[Columns.reps] = reps
        container[Columns.duration] = duration
        container[Columns.weight] = weight
        container[Columns.completedAt] = completedAt
    }
}

// Combined model for UI
struct SessionWithDetails: Identifiable {
    var session: WorkoutSession
    var template: WorkoutTemplate?
    var sets: [SessionSetWithExercise]
    var cardioSessions: [CardioSession]

    var id: UUID { session.id }

    var totalSets: Int { sets.count }

    var totalReps: Int {
        sets.compactMap { $0.sessionSet.reps }.reduce(0, +)
    }

    var exercisesCompleted: Int {
        Set(sets.map { $0.sessionSet.exerciseId }).count
    }

    var totalVolume: Double {
        sets.reduce(0) { total, setDetail in
            let reps = Double(setDetail.sessionSet.reps ?? 0)
            let weight = setDetail.sessionSet.weight ?? 0
            return total + (reps * weight)
        }
    }
}

struct SessionSetWithExercise: Identifiable, Hashable {
    var sessionSet: SessionSet
    var exercise: Exercise

    var id: UUID { sessionSet.id }
}

struct WorkoutDayPlan: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var templateId: UUID
    var shuffleCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        templateId: UUID,
        shuffleCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.templateId = templateId
        self.shuffleCount = shuffleCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension WorkoutDayPlan: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_day_plans"

    enum Columns: String, ColumnExpression {
        case id, date, templateId = "template_id", shuffleCount = "shuffle_count"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        date = try row[Columns.date]
        templateId = try row[Columns.templateId]
        shuffleCount = try row[Columns.shuffleCount]
        createdAt = try row[Columns.createdAt]
        updatedAt = try row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.date] = date
        container[Columns.templateId] = templateId
        container[Columns.shuffleCount] = shuffleCount
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

struct WorkoutDayPlanExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var planId: UUID
    var exerciseId: UUID
    var sortOrder: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetDuration: Int?
    var targetWeight: Double?
    var isAnchor: Bool

    init(
        id: UUID = UUID(),
        planId: UUID,
        exerciseId: UUID,
        sortOrder: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetDuration: Int? = nil,
        targetWeight: Double? = nil,
        isAnchor: Bool = false
    ) {
        self.id = id
        self.planId = planId
        self.exerciseId = exerciseId
        self.sortOrder = sortOrder
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetDuration = targetDuration
        self.targetWeight = targetWeight
        self.isAnchor = isAnchor
    }
}

extension WorkoutDayPlanExercise: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_day_plan_exercises"

    enum Columns: String, ColumnExpression {
        case id, planId = "plan_id", exerciseId = "exercise_id", sortOrder = "sort_order"
        case targetSets = "target_sets", targetReps = "target_reps", targetDuration = "target_duration"
        case targetWeight = "target_weight", isAnchor = "is_anchor"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        planId = try row[Columns.planId]
        exerciseId = try row[Columns.exerciseId]
        sortOrder = try row[Columns.sortOrder]
        targetSets = row[Columns.targetSets]
        targetReps = row[Columns.targetReps]
        targetDuration = row[Columns.targetDuration]
        targetWeight = row[Columns.targetWeight]
        isAnchor = try row[Columns.isAnchor]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.planId] = planId
        container[Columns.exerciseId] = exerciseId
        container[Columns.sortOrder] = sortOrder
        container[Columns.targetSets] = targetSets
        container[Columns.targetReps] = targetReps
        container[Columns.targetDuration] = targetDuration
        container[Columns.targetWeight] = targetWeight
        container[Columns.isAnchor] = isAnchor
    }
}

struct WorkoutDayPlanExerciseDetail: Identifiable, Hashable, Codable {
    var planExercise: WorkoutDayPlanExercise
    var exercise: Exercise

    var id: UUID { planExercise.id }

    var asTemplateExerciseDetail: TemplateExerciseDetail {
        let templateExercise = TemplateExercise(
            id: planExercise.id,
            templateId: planExercise.planId,
            exerciseId: exercise.id,
            sortOrder: planExercise.sortOrder,
            targetSets: planExercise.targetSets,
            targetReps: planExercise.targetReps,
            targetDuration: planExercise.targetDuration,
            targetWeight: planExercise.targetWeight
        )

        return TemplateExerciseDetail(templateExercise: templateExercise, exercise: exercise)
    }
}

struct WorkoutDayPlanWithExercises: Identifiable, Hashable {
    var plan: WorkoutDayPlan
    var template: WorkoutTemplate
    var exercises: [WorkoutDayPlanExerciseDetail]

    var id: UUID { plan.id }
}

struct WorkoutCalendarDaySummary: Identifiable, Hashable {
    var date: Date
    var workoutCount: Int

    var id: Date { date }
}

// Helper function
func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}
