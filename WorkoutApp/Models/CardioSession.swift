import Foundation
import GRDB

enum CardioType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case treadmill = "treadmill"
    case bike = "bike"
    case rowing = "rowing"
    case elliptical = "elliptical"
    case stairmaster = "stairmaster"
    case other = "other"

    var displayName: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .bike: return "Bike"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairmaster: return "Stairmaster"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .treadmill: return "figure.run"
        case .bike: return "bicycle"
        case .rowing: return "figure.rowing"
        case .elliptical: return "figure.elliptical"
        case .stairmaster: return "figure.stair.stepper"
        case .other: return "figure.mixed.cardio"
        }
    }
}

struct CardioSession: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var cardioType: CardioType
    var duration: Int
    var distance: Double?
    var calories: Int?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var incline: Double?
    var resistance: Int?
    var notes: String?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        cardioType: CardioType,
        duration: Int,
        distance: Double? = nil,
        calories: Int? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        incline: Double? = nil,
        resistance: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.cardioType = cardioType
        self.duration = duration
        self.distance = distance
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.incline = incline
        self.resistance = resistance
        self.notes = notes
    }

    var formattedDuration: String {
        formatDuration(duration)
    }

    var formattedDistance: String? {
        guard let distance = distance else { return nil }
        return String(format: "%.2f km", distance)
    }
}

// MARK: - GRDB Support
extension CardioSession: FetchableRecord, PersistableRecord {
    static let databaseTableName = "cardio_sessions"

    enum Columns: String, ColumnExpression {
        case id, sessionId = "session_id", cardioType = "cardio_type"
        case duration, distance, calories
        case avgHeartRate = "avg_heart_rate", maxHeartRate = "max_heart_rate"
        case incline, resistance, notes
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        sessionId = try row[Columns.sessionId]
        cardioType = try row[Columns.cardioType]
        duration = try row[Columns.duration]
        distance = row[Columns.distance]
        calories = row[Columns.calories]
        avgHeartRate = row[Columns.avgHeartRate]
        maxHeartRate = row[Columns.maxHeartRate]
        incline = row[Columns.incline]
        resistance = row[Columns.resistance]
        notes = row[Columns.notes]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.sessionId] = sessionId
        container[Columns.cardioType] = cardioType
        container[Columns.duration] = duration
        container[Columns.distance] = distance
        container[Columns.calories] = calories
        container[Columns.avgHeartRate] = avgHeartRate
        container[Columns.maxHeartRate] = maxHeartRate
        container[Columns.incline] = incline
        container[Columns.resistance] = resistance
        container[Columns.notes] = notes
    }
}
