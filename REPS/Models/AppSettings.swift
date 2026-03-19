import Foundation
import GRDB

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case german = "de"
    case spanish = "es"
    case arabic = "ar"
    case hindi = "hi"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .german:
            return "de"
        case .spanish:
            return "es"
        case .arabic:
            return "ar"
        case .hindi:
            return "hi"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .german:
            return "Deutsch"
        case .spanish:
            return "Español"
        case .arabic:
            return "العربية"
        case .hindi:
            return "हिन्दी"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    static func bestMatch(for localeIdentifier: String) -> AppLanguage {
        let normalized = localeIdentifier.lowercased()
        if normalized.hasPrefix("de") {
            return .german
        }
        if normalized.hasPrefix("es") {
            return .spanish
        }
        if normalized.hasPrefix("ar") {
            return .arabic
        }
        if normalized.hasPrefix("hi") {
            return .hindi
        }
        if normalized.hasPrefix("zh") {
            return .simplifiedChinese
        }
        return .english
    }
}

enum SocialVisibility: String, CaseIterable, Identifiable, Codable {
    case friendsMedium = "friends_medium"

    var id: String { rawValue }
}

enum TrainingGoalFocus: String, CaseIterable, Identifiable, Codable {
    case hypertrophy
    case strength
    case recomposition
    case athletic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hypertrophy:
            return "Muscle"
        case .strength:
            return "Strength"
        case .recomposition:
            return "Lean"
        case .athletic:
            return "Athletic"
        }
    }

    var subtitle: String {
        switch self {
        case .hypertrophy:
            return "Mehr Volumen, sauberer Pump und progressive Hypertrophie."
        case .strength:
            return "Mehr Fokus auf Hauptlifts, Kraft und klare Leistungssteigerung."
        case .recomposition:
            return "Starker Mix aus Performance, Volumen und Kalorienkontrolle."
        case .athletic:
            return "Leistung, Energie, Core und robuste Ganzkoerper-Performance."
        }
    }
}

enum WorkoutRotationStyle: String, CaseIterable, Identifiable, Codable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative:
            return "Stable"
        case .balanced:
            return "Balanced"
        case .aggressive:
            return "Fresh"
        }
    }

    var subtitle: String {
        switch self {
        case .conservative:
            return "Haelt Assistenz-Uebungen laenger stabil, damit Fortschritt messbar bleibt."
        case .balanced:
            return "Wechselt smart zwischen Progression und frischen Reizen."
        case .aggressive:
            return "Mehr Variation bei jeder neuen Session fuer maximale Abwechslung."
        }
    }

    var cadenceSessions: Int {
        switch self {
        case .conservative:
            return 3
        case .balanced:
            return 2
        case .aggressive:
            return 1
        }
    }
}

struct AppSettings {
    var defaultRestTime: Int = 90
    var workoutReminderEnabled: Bool = false
    var workoutReminderTime: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    var restTimerSound: Bool = true
    var restTimerHaptic: Bool = true
    var weekStartsOn: Int = 1 // 0 = Sunday, 1 = Monday
    var trainingSetupCompleted: Bool = false
    var goalFocus: String = TrainingGoalFocus.hypertrophy.rawValue
    var preferredSessionLengthMinutes: Int = 60
    var targetTrainingDaysPerWeek: Int = 4
    var rotationStyle: String = WorkoutRotationStyle.balanced.rawValue
    var personalPlanLocked: Bool = false
    var preferredLanguage: String = AppLanguage.bestMatch(for: Locale.preferredLanguages.first ?? Locale.current.identifier).rawValue
    var motivationPushEnabled: Bool = true
    var socialPushEnabled: Bool = true
    var socialVisibility: String = SocialVisibility.friendsMedium.rawValue
    var quietHoursStart: String = "21:00"
    var quietHoursEnd: String = "08:00"

    static let defaultRestTimeKey = "defaultRestTime"
    static let workoutReminderEnabledKey = "workoutReminderEnabled"
    static let workoutReminderTimeKey = "workoutReminderTime"
    static let restTimerSoundKey = "restTimerSound"
    static let restTimerHapticKey = "restTimerHaptic"
    static let weekStartsOnKey = "weekStartsOn"
    static let trainingSetupCompletedKey = "trainingSetupCompleted"
    static let goalFocusKey = "goalFocus"
    static let preferredSessionLengthMinutesKey = "preferredSessionLengthMinutes"
    static let targetTrainingDaysPerWeekKey = "targetTrainingDaysPerWeek"
    static let rotationStyleKey = "rotationStyle"
    static let personalPlanLockedKey = "personalPlanLocked"
    static let preferredLanguageKey = "preferredLanguage"
    static let motivationPushEnabledKey = "motivationPushEnabled"
    static let socialPushEnabledKey = "socialPushEnabled"
    static let socialVisibilityKey = "socialVisibility"
    static let quietHoursStartKey = "quietHoursStart"
    static let quietHoursEndKey = "quietHoursEnd"

    var goalFocusValue: TrainingGoalFocus {
        get { TrainingGoalFocus(rawValue: goalFocus) ?? .hypertrophy }
        set { goalFocus = newValue.rawValue }
    }

    var rotationStyleValue: WorkoutRotationStyle {
        get { WorkoutRotationStyle(rawValue: rotationStyle) ?? .balanced }
        set { rotationStyle = newValue.rawValue }
    }

    var preferredLanguageValue: AppLanguage {
        get { AppLanguage(rawValue: preferredLanguage) ?? .english }
        set { preferredLanguage = newValue.rawValue }
    }

    var socialVisibilityValue: SocialVisibility {
        get { SocialVisibility(rawValue: socialVisibility) ?? .friendsMedium }
        set { socialVisibility = newValue.rawValue }
    }
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
