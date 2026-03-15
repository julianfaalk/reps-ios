import Foundation

struct WorkoutProfile: Codable, Hashable {
    var displayName: String = ""
    var goal: String = ""
    var experienceLevel: String = ""
    var timezone: String = TimeZone.current.identifier

    enum CodingKeys: String, CodingKey {
        case displayName, goal, experienceLevel, timezone
    }

    init(
        displayName: String = "",
        goal: String = "",
        experienceLevel: String = "",
        timezone: String = TimeZone.current.identifier
    ) {
        self.displayName = displayName
        self.goal = goal
        self.experienceLevel = experienceLevel
        self.timezone = timezone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        experienceLevel = try container.decodeIfPresent(String.self, forKey: .experienceLevel) ?? ""
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? TimeZone.current.identifier
    }
}

struct WorkoutCloudPreferences: Codable, Hashable {
    var defaultRestTime: Int = 90
    var workoutReminderEnabled: Bool = false
    var workoutReminderTime: String = "07:00"
    var restTimerSound: Bool = true
    var restTimerHaptic: Bool = true
    var weekStartsOn: Int = 1

    enum CodingKeys: String, CodingKey {
        case defaultRestTime, workoutReminderEnabled, workoutReminderTime, restTimerSound, restTimerHaptic, weekStartsOn
    }

    init(
        defaultRestTime: Int = 90,
        workoutReminderEnabled: Bool = false,
        workoutReminderTime: String = "07:00",
        restTimerSound: Bool = true,
        restTimerHaptic: Bool = true,
        weekStartsOn: Int = 1
    ) {
        self.defaultRestTime = defaultRestTime
        self.workoutReminderEnabled = workoutReminderEnabled
        self.workoutReminderTime = workoutReminderTime
        self.restTimerSound = restTimerSound
        self.restTimerHaptic = restTimerHaptic
        self.weekStartsOn = weekStartsOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultRestTime = try container.decodeIfPresent(Int.self, forKey: .defaultRestTime) ?? 90
        workoutReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .workoutReminderEnabled) ?? false
        workoutReminderTime = try container.decodeIfPresent(String.self, forKey: .workoutReminderTime) ?? "07:00"
        restTimerSound = try container.decodeIfPresent(Bool.self, forKey: .restTimerSound) ?? true
        restTimerHaptic = try container.decodeIfPresent(Bool.self, forKey: .restTimerHaptic) ?? true
        weekStartsOn = try container.decodeIfPresent(Int.self, forKey: .weekStartsOn) ?? 1
    }
}

struct WorkoutCloudStats: Codable, Hashable {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalWorkouts: Int = 0
    var totalMinutes: Int = 0
    var personalRecords: Int = 0
    var measurementsLogged: Int = 0
    var lastWorkoutAt: Date?
    var lastWorkoutTemplate: String = ""
    var currentWeightKg: Double?
    var bodyFatPercentage: Double?
    var recentWorkoutDates: [String] = []
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case currentStreak, longestStreak, totalWorkouts, totalMinutes, personalRecords, measurementsLogged
        case lastWorkoutAt, lastWorkoutTemplate, currentWeightKg, bodyFatPercentage, recentWorkoutDates, syncedAt
    }

    init(
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        totalWorkouts: Int = 0,
        totalMinutes: Int = 0,
        personalRecords: Int = 0,
        measurementsLogged: Int = 0,
        lastWorkoutAt: Date? = nil,
        lastWorkoutTemplate: String = "",
        currentWeightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        recentWorkoutDates: [String] = [],
        syncedAt: Date? = nil
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalWorkouts = totalWorkouts
        self.totalMinutes = totalMinutes
        self.personalRecords = personalRecords
        self.measurementsLogged = measurementsLogged
        self.lastWorkoutAt = lastWorkoutAt
        self.lastWorkoutTemplate = lastWorkoutTemplate
        self.currentWeightKg = currentWeightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.recentWorkoutDates = recentWorkoutDates
        self.syncedAt = syncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try container.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        totalWorkouts = try container.decodeIfPresent(Int.self, forKey: .totalWorkouts) ?? 0
        totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes) ?? 0
        personalRecords = try container.decodeIfPresent(Int.self, forKey: .personalRecords) ?? 0
        measurementsLogged = try container.decodeIfPresent(Int.self, forKey: .measurementsLogged) ?? 0
        lastWorkoutAt = try container.decodeIfPresent(Date.self, forKey: .lastWorkoutAt)
        lastWorkoutTemplate = try container.decodeIfPresent(String.self, forKey: .lastWorkoutTemplate) ?? ""
        currentWeightKg = try container.decodeIfPresent(Double.self, forKey: .currentWeightKg)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        recentWorkoutDates = try container.decodeIfPresent([String].self, forKey: .recentWorkoutDates) ?? []
        syncedAt = try container.decodeIfPresent(Date.self, forKey: .syncedAt)
    }
}

struct WorkoutDeviceSnapshot: Codable, Hashable {
    var platform: String = ""
    var appVersion: String = ""
    var build: String = ""
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case platform, appVersion, build, syncedAt
    }

    init(
        platform: String = "",
        appVersion: String = "",
        build: String = "",
        syncedAt: Date? = nil
    ) {
        self.platform = platform
        self.appVersion = appVersion
        self.build = build
        self.syncedAt = syncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? ""
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        build = try container.decodeIfPresent(String.self, forKey: .build) ?? ""
        syncedAt = try container.decodeIfPresent(Date.self, forKey: .syncedAt)
    }
}

struct WorkoutCloudUser: Codable, Identifiable, Hashable {
    var id: String?
    var name: String
    var email: String?
    var authProvider: String
    var onboardingCompleted: Bool
    var profile: WorkoutProfile
    var preferences: WorkoutCloudPreferences
    var stats: WorkoutCloudStats
    var lastDevice: WorkoutDeviceSnapshot?
    var premiumExpiry: Date?
    var createdAt: Date?
    var updatedAt: Date?

    var resolvedDisplayName: String {
        if !profile.displayName.isEmpty {
            return profile.displayName
        }
        return name
    }

    var isPremiumActive: Bool {
        guard let premiumExpiry else { return false }
        return premiumExpiry > Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, email, authProvider, onboardingCompleted, profile, preferences, stats, lastDevice
        case premiumExpiry, createdAt, updatedAt
    }

    init(
        id: String? = nil,
        name: String = "",
        email: String? = nil,
        authProvider: String = "apple",
        onboardingCompleted: Bool = false,
        profile: WorkoutProfile = WorkoutProfile(),
        preferences: WorkoutCloudPreferences = WorkoutCloudPreferences(),
        stats: WorkoutCloudStats = WorkoutCloudStats(),
        lastDevice: WorkoutDeviceSnapshot? = nil,
        premiumExpiry: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.authProvider = authProvider
        self.onboardingCompleted = onboardingCompleted
        self.profile = profile
        self.preferences = preferences
        self.stats = stats
        self.lastDevice = lastDevice
        self.premiumExpiry = premiumExpiry
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        authProvider = try container.decodeIfPresent(String.self, forKey: .authProvider) ?? "apple"
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        profile = try container.decodeIfPresent(WorkoutProfile.self, forKey: .profile) ?? WorkoutProfile()
        preferences = try container.decodeIfPresent(WorkoutCloudPreferences.self, forKey: .preferences) ?? WorkoutCloudPreferences()
        stats = try container.decodeIfPresent(WorkoutCloudStats.self, forKey: .stats) ?? WorkoutCloudStats()
        lastDevice = try container.decodeIfPresent(WorkoutDeviceSnapshot.self, forKey: .lastDevice)
        premiumExpiry = try container.decodeIfPresent(Date.self, forKey: .premiumExpiry)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct WorkoutSubscriptionStatus: Codable, Hashable {
    var isActive: Bool
    var productId: String?
    var expiresAt: Date?
}

struct WorkoutSyncRequest: Encodable {
    var profile: WorkoutProfile?
    var preferences: WorkoutCloudPreferences?
    var stats: WorkoutCloudStats?
    var device: WorkoutDeviceSnapshot?
}
