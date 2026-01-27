import Foundation
import GRDB

struct PersonalRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var exerciseId: UUID
    var weight: Double
    var reps: Int
    var achievedAt: Date
    var sessionId: UUID

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        weight: Double,
        reps: Int,
        achievedAt: Date = Date(),
        sessionId: UUID
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.weight = weight
        self.reps = reps
        self.achievedAt = achievedAt
        self.sessionId = sessionId
    }

    var formattedWeight: String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(weight)) kg"
            : String(format: "%.1f kg", weight)
    }

    // Estimated 1RM using Brzycki formula
    var estimated1RM: Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (36.0 / (37.0 - Double(reps)))
    }
}

// MARK: - GRDB Support
extension PersonalRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "personal_records"

    enum Columns: String, ColumnExpression {
        case id, exerciseId = "exercise_id", weight, reps
        case achievedAt = "achieved_at", sessionId = "session_id"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        exerciseId = try row[Columns.exerciseId]
        weight = try row[Columns.weight]
        reps = try row[Columns.reps]
        achievedAt = try row[Columns.achievedAt]
        sessionId = try row[Columns.sessionId]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.exerciseId] = exerciseId
        container[Columns.weight] = weight
        container[Columns.reps] = reps
        container[Columns.achievedAt] = achievedAt
        container[Columns.sessionId] = sessionId
    }
}

// Combined model for UI
struct PersonalRecordWithExercise: Identifiable {
    var record: PersonalRecord
    var exercise: Exercise

    var id: UUID { record.id }
}
