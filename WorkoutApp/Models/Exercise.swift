import Foundation
import GRDB

enum ExerciseType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case reps = "reps"
    case timed = "timed"

    var displayName: String {
        switch self {
        case .reps: return "Reps"
        case .timed: return "Timed"
        }
    }
}

enum MuscleGroup: String, Codable, CaseIterable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case core = "Core"
    case quadriceps = "Quadriceps"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case fullBody = "Full Body"
}

struct Exercise: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var exerciseType: ExerciseType
    var muscleGroups: [String]
    var equipment: String?
    var notes: String?
    var movementPattern: String?
    var variationGroup: String?
    var splitTags: [String]
    var isCompound: Bool
    var isAnchorCandidate: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        exerciseType: ExerciseType = .reps,
        muscleGroups: [String] = [],
        equipment: String? = nil,
        notes: String? = nil,
        movementPattern: String? = nil,
        variationGroup: String? = nil,
        splitTags: [String] = [],
        isCompound: Bool = false,
        isAnchorCandidate: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.exerciseType = exerciseType
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.notes = notes
        self.movementPattern = movementPattern
        self.variationGroup = variationGroup
        self.splitTags = splitTags
        self.isCompound = isCompound
        self.isAnchorCandidate = isAnchorCandidate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Support
extension Exercise: FetchableRecord, PersistableRecord {
    static let databaseTableName = "exercises"

    enum Columns: String, ColumnExpression {
        case id, name, exerciseType = "exercise_type", muscleGroups = "muscle_groups"
        case equipment, notes
        case movementPattern = "movement_pattern"
        case variationGroup = "variation_group"
        case splitTags = "split_tags"
        case isCompound = "is_compound"
        case isAnchorCandidate = "is_anchor_candidate"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        name = try row[Columns.name]
        exerciseType = try row[Columns.exerciseType]

        if let muscleGroupsJson: String = row[Columns.muscleGroups] {
            if let data = muscleGroupsJson.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                muscleGroups = decoded
            } else {
                muscleGroups = []
            }
        } else {
            muscleGroups = []
        }

        equipment = row[Columns.equipment]
        notes = row[Columns.notes]
        movementPattern = row[Columns.movementPattern]
        variationGroup = row[Columns.variationGroup]
        if let splitTagsJson: String = row[Columns.splitTags] {
            if let data = splitTagsJson.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                splitTags = decoded
            } else {
                splitTags = []
            }
        } else {
            splitTags = []
        }
        isCompound = row[Columns.isCompound] ?? false
        isAnchorCandidate = row[Columns.isAnchorCandidate] ?? false
        createdAt = try row[Columns.createdAt]
        updatedAt = try row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.exerciseType] = exerciseType

        if let data = try? JSONEncoder().encode(muscleGroups),
           let json = String(data: data, encoding: .utf8) {
            container[Columns.muscleGroups] = json
        }

        container[Columns.equipment] = equipment
        container[Columns.notes] = notes
        container[Columns.movementPattern] = movementPattern
        container[Columns.variationGroup] = variationGroup
        if let data = try? JSONEncoder().encode(splitTags),
           let json = String(data: data, encoding: .utf8) {
            container[Columns.splitTags] = json
        }
        container[Columns.isCompound] = isCompound
        container[Columns.isAnchorCandidate] = isAnchorCandidate
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}
