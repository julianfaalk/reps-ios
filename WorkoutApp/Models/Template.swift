import Foundation
import GRDB

struct WorkoutTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Support
extension WorkoutTemplate: FetchableRecord, PersistableRecord {
    static let databaseTableName = "templates"

    enum Columns: String, ColumnExpression {
        case id, name, createdAt = "created_at", updatedAt = "updated_at"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        name = try row[Columns.name]
        createdAt = try row[Columns.createdAt]
        updatedAt = try row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

struct TemplateExercise: Identifiable, Codable, Hashable {
    var id: UUID
    var templateId: UUID
    var exerciseId: UUID
    var sortOrder: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetDuration: Int?
    var targetWeight: Double?

    init(
        id: UUID = UUID(),
        templateId: UUID,
        exerciseId: UUID,
        sortOrder: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        targetDuration: Int? = nil,
        targetWeight: Double? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.exerciseId = exerciseId
        self.sortOrder = sortOrder
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetDuration = targetDuration
        self.targetWeight = targetWeight
    }
}

// MARK: - GRDB Support
extension TemplateExercise: FetchableRecord, PersistableRecord {
    static let databaseTableName = "template_exercises"

    enum Columns: String, ColumnExpression {
        case id, templateId = "template_id", exerciseId = "exercise_id"
        case sortOrder = "sort_order", targetSets = "target_sets"
        case targetReps = "target_reps", targetDuration = "target_duration"
        case targetWeight = "target_weight"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        templateId = try row[Columns.templateId]
        exerciseId = try row[Columns.exerciseId]
        sortOrder = try row[Columns.sortOrder]
        targetSets = row[Columns.targetSets]
        targetReps = row[Columns.targetReps]
        targetDuration = row[Columns.targetDuration]
        targetWeight = row[Columns.targetWeight]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.templateId] = templateId
        container[Columns.exerciseId] = exerciseId
        container[Columns.sortOrder] = sortOrder
        container[Columns.targetSets] = targetSets
        container[Columns.targetReps] = targetReps
        container[Columns.targetDuration] = targetDuration
        container[Columns.targetWeight] = targetWeight
    }
}

// Combined model for UI
struct TemplateWithExercises: Identifiable {
    var template: WorkoutTemplate
    var exercises: [TemplateExerciseDetail]

    var id: UUID { template.id }
    var name: String { template.name }
}

struct TemplateExerciseDetail: Identifiable, Hashable {
    var templateExercise: TemplateExercise
    var exercise: Exercise

    var id: UUID { templateExercise.id }
}
