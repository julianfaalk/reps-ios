import Foundation
import GRDB

struct AppSettings {
    var defaultRestTime: Int = 90
    var workoutReminderEnabled: Bool = false
    var workoutReminderTime: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    var restTimerSound: Bool = true
    var restTimerHaptic: Bool = true
    var weekStartsOn: Int = 1 // 0 = Sunday, 1 = Monday

    static let defaultRestTimeKey = "defaultRestTime"
    static let workoutReminderEnabledKey = "workoutReminderEnabled"
    static let workoutReminderTimeKey = "workoutReminderTime"
    static let restTimerSoundKey = "restTimerSound"
    static let restTimerHapticKey = "restTimerHaptic"
    static let weekStartsOnKey = "weekStartsOn"
}

struct SettingEntry: Codable, Hashable {
    var key: String
    var value: String
}

// MARK: - GRDB Support
extension SettingEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "settings"

    enum Columns: String, ColumnExpression {
        case key, value
    }

    init(row: Row) throws {
        key = try row[Columns.key]
        value = try row[Columns.value]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.key] = key
        container[Columns.value] = value
    }
}
