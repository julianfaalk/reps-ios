import Foundation
import GRDB

struct Schedule: Identifiable, Codable, Hashable {
    var id: UUID
    var dayOfWeek: Int // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    var templateId: UUID?
    var isRestDay: Bool

    init(
        id: UUID = UUID(),
        dayOfWeek: Int,
        templateId: UUID? = nil,
        isRestDay: Bool = false
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.templateId = templateId
        self.isRestDay = isRestDay
    }

    var dayName: String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayOfWeek >= 0 && dayOfWeek < 7 else { return "Unknown" }
        return days[dayOfWeek]
    }

    var shortDayName: String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard dayOfWeek >= 0 && dayOfWeek < 7 else { return "?" }
        return days[dayOfWeek]
    }
}

// MARK: - GRDB Support
extension Schedule: FetchableRecord, PersistableRecord {
    static let databaseTableName = "schedule"

    enum Columns: String, ColumnExpression {
        case id, dayOfWeek = "day_of_week", templateId = "template_id", isRestDay = "is_rest_day"
    }

    init(row: Row) throws {
        id = try row[Columns.id]
        dayOfWeek = try row[Columns.dayOfWeek]
        templateId = row[Columns.templateId]
        isRestDay = try row[Columns.isRestDay]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.dayOfWeek] = dayOfWeek
        container[Columns.templateId] = templateId
        container[Columns.isRestDay] = isRestDay
    }
}

// Combined model for UI
struct ScheduleDay: Identifiable {
    var schedule: Schedule?
    var template: WorkoutTemplate?
    var dayOfWeek: Int

    var id: Int { dayOfWeek }

    var isRestDay: Bool {
        schedule?.isRestDay ?? (template == nil)
    }

    var dayName: String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayOfWeek >= 0 && dayOfWeek < 7 else { return "Unknown" }
        return days[dayOfWeek]
    }

    var shortDayName: String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard dayOfWeek >= 0 && dayOfWeek < 7 else { return "?" }
        return days[dayOfWeek]
    }
}
