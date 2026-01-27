import Foundation
import GRDB

struct Measurement: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var bodyWeight: Double?
    var bodyFat: Double?
    var neck: Double?
    var shoulders: Double?
    var chest: Double?
    var waist: Double?
    var hips: Double?
    var armLeft: Double?
    var armRight: Double?
    var forearmLeft: Double?
    var forearmRight: Double?
    var thighLeft: Double?
    var thighRight: Double?
    var calfLeft: Double?
    var calfRight: Double?
    var notes: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        bodyWeight: Double? = nil,
        bodyFat: Double? = nil,
        neck: Double? = nil,
        shoulders: Double? = nil,
        chest: Double? = nil,
        waist: Double? = nil,
        hips: Double? = nil,
        armLeft: Double? = nil,
        armRight: Double? = nil,
        forearmLeft: Double? = nil,
        forearmRight: Double? = nil,
        thighLeft: Double? = nil,
        thighRight: Double? = nil,
        calfLeft: Double? = nil,
        calfRight: Double? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.bodyWeight = bodyWeight
        self.bodyFat = bodyFat
        self.neck = neck
        self.shoulders = shoulders
        self.chest = chest
        self.waist = waist
        self.hips = hips
        self.armLeft = armLeft
        self.armRight = armRight
        self.forearmLeft = forearmLeft
        self.forearmRight = forearmRight
        self.thighLeft = thighLeft
        self.thighRight = thighRight
        self.calfLeft = calfLeft
        self.calfRight = calfRight
        self.notes = notes
        self.createdAt = createdAt
    }

    var formattedWeight: String? {
        guard let weight = bodyWeight else { return nil }
        return String(format: "%.1f kg", weight)
    }
}

// MARK: - GRDB Support
extension Measurement: FetchableRecord, PersistableRecord {
    static let databaseTableName = "measurements"

    enum Columns: String, ColumnExpression {
        case id, date, bodyWeight = "body_weight", bodyFat = "body_fat"
        case neck, shoulders, chest, waist, hips
        case armLeft = "arm_left", armRight = "arm_right"
        case forearmLeft = "forearm_left", forearmRight = "forearm_right"
        case thighLeft = "thigh_left", thighRight = "thigh_right"
        case calfLeft = "calf_left", calfRight = "calf_right"
        case notes, createdAt = "created_at"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        date = try row[Columns.date]
        bodyWeight = row[Columns.bodyWeight]
        bodyFat = row[Columns.bodyFat]
        neck = row[Columns.neck]
        shoulders = row[Columns.shoulders]
        chest = row[Columns.chest]
        waist = row[Columns.waist]
        hips = row[Columns.hips]
        armLeft = row[Columns.armLeft]
        armRight = row[Columns.armRight]
        forearmLeft = row[Columns.forearmLeft]
        forearmRight = row[Columns.forearmRight]
        thighLeft = row[Columns.thighLeft]
        thighRight = row[Columns.thighRight]
        calfLeft = row[Columns.calfLeft]
        calfRight = row[Columns.calfRight]
        notes = row[Columns.notes]
        createdAt = try row[Columns.createdAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.date] = date
        container[Columns.bodyWeight] = bodyWeight
        container[Columns.bodyFat] = bodyFat
        container[Columns.neck] = neck
        container[Columns.shoulders] = shoulders
        container[Columns.chest] = chest
        container[Columns.waist] = waist
        container[Columns.hips] = hips
        container[Columns.armLeft] = armLeft
        container[Columns.armRight] = armRight
        container[Columns.forearmLeft] = forearmLeft
        container[Columns.forearmRight] = forearmRight
        container[Columns.thighLeft] = thighLeft
        container[Columns.thighRight] = thighRight
        container[Columns.calfLeft] = calfLeft
        container[Columns.calfRight] = calfRight
        container[Columns.notes] = notes
        container[Columns.createdAt] = createdAt
    }
}

enum PhotoType: String, Codable, CaseIterable {
    case front = "front"
    case side = "side"
    case back = "back"

    var displayName: String {
        rawValue.capitalized
    }
}

struct ProgressPhoto: Identifiable, Codable, Hashable {
    var id: UUID
    var measurementId: UUID
    var photoData: Data
    var photoType: PhotoType?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        measurementId: UUID,
        photoData: Data,
        photoType: PhotoType? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.measurementId = measurementId
        self.photoData = photoData
        self.photoType = photoType
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Support
extension ProgressPhoto: FetchableRecord, PersistableRecord {
    static let databaseTableName = "progress_photos"

    enum Columns: String, ColumnExpression {
        case id, measurementId = "measurement_id", photoData = "photo_data"
        case photoType = "photo_type", createdAt = "created_at"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        measurementId = try row[Columns.measurementId]
        photoData = try row[Columns.photoData]
        if let photoTypeString: String = row[Columns.photoType] {
            photoType = PhotoType(rawValue: photoTypeString)
        } else {
            photoType = nil
        }
        createdAt = try row[Columns.createdAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.measurementId] = measurementId
        container[Columns.photoData] = photoData
        container[Columns.photoType] = photoType?.rawValue
        container[Columns.createdAt] = createdAt
    }
}

// Combined model for UI
struct MeasurementWithPhotos: Identifiable {
    var measurement: Measurement
    var photos: [ProgressPhoto]

    var id: UUID { measurement.id }
}
