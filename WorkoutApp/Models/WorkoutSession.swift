import Foundation
import GRDB

struct WorkoutSession: Identifiable, Codable, Hashable {
    var id: UUID
    var templateId: UUID?
    var startedAt: Date
    var completedAt: Date?
    var duration: Int?
    var notes: String?

    init(
        id: UUID = UUID(),
        templateId: UUID? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        duration: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.templateId = templateId
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
        case id, templateId = "template_id", startedAt = "started_at"
        case completedAt = "completed_at", duration, notes
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        templateId = row[Columns.templateId]
        startedAt = try row[Columns.startedAt]
        completedAt = row[Columns.completedAt]
        duration = row[Columns.duration]
        notes = row[Columns.notes]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.templateId] = templateId
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
        sets.compactMap { $0.set.reps }.reduce(0, +)
    }

    var exercisesCompleted: Int {
        Set(sets.map { $0.set.exerciseId }).count
    }

    var totalVolume: Double {
        sets.reduce(0) { total, setDetail in
            let reps = Double(setDetail.set.reps ?? 0)
            let weight = setDetail.set.weight ?? 0
            return total + (reps * weight)
        }
    }
}

struct SessionSetWithExercise: Identifiable, Hashable {
    var set: SessionSet
    var exercise: Exercise

    var id: UUID { set.id }
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
