import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    private var dbQueue: DatabaseQueue!

    private init() {
        do {
            try setupDatabase()
        } catch {
            fatalError("Failed to setup database: \(error)")
        }
    }

    private func setupDatabase() throws {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseURL = documentsURL.appendingPathComponent("workout.db")

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Exercises
            try db.create(table: "exercises") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("exercise_type", .text).notNull().defaults(to: "reps")
                t.column("muscle_groups", .text)
                t.column("equipment", .text)
                t.column("notes", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Templates
            try db.create(table: "templates") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Template Exercises
            try db.create(table: "template_exercises") { t in
                t.column("id", .text).primaryKey()
                t.column("template_id", .text).notNull()
                    .references("templates", onDelete: .cascade)
                t.column("exercise_id", .text).notNull()
                    .references("exercises", onDelete: .cascade)
                t.column("sort_order", .integer).notNull()
                t.column("target_sets", .integer)
                t.column("target_reps", .integer)
                t.column("target_duration", .integer)
                t.column("target_weight", .double)
            }

            // Schedule
            try db.create(table: "schedule") { t in
                t.column("id", .text).primaryKey()
                t.column("day_of_week", .integer).notNull()
                t.column("template_id", .text)
                    .references("templates", onDelete: .setNull)
                t.column("is_rest_day", .boolean).notNull().defaults(to: false)
            }

            // Workout Sessions
            try db.create(table: "workout_sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("template_id", .text)
                    .references("templates", onDelete: .setNull)
                t.column("started_at", .datetime).notNull()
                t.column("completed_at", .datetime)
                t.column("duration", .integer)
                t.column("notes", .text)
            }

            // Session Sets
            try db.create(table: "session_sets") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                t.column("exercise_id", .text).notNull()
                    .references("exercises", onDelete: .cascade)
                t.column("set_number", .integer).notNull()
                t.column("reps", .integer)
                t.column("duration", .integer)
                t.column("weight", .double)
                t.column("completed_at", .datetime).notNull()
            }

            // Cardio Sessions
            try db.create(table: "cardio_sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                t.column("cardio_type", .text).notNull()
                t.column("duration", .integer).notNull()
                t.column("distance", .double)
                t.column("calories", .integer)
                t.column("avg_heart_rate", .integer)
                t.column("max_heart_rate", .integer)
                t.column("incline", .double)
                t.column("resistance", .integer)
                t.column("notes", .text)
            }

            // Measurements
            try db.create(table: "measurements") { t in
                t.column("id", .text).primaryKey()
                t.column("date", .datetime).notNull()
                t.column("body_weight", .double)
                t.column("body_fat", .double)
                t.column("neck", .double)
                t.column("shoulders", .double)
                t.column("chest", .double)
                t.column("waist", .double)
                t.column("hips", .double)
                t.column("arm_left", .double)
                t.column("arm_right", .double)
                t.column("forearm_left", .double)
                t.column("forearm_right", .double)
                t.column("thigh_left", .double)
                t.column("thigh_right", .double)
                t.column("calf_left", .double)
                t.column("calf_right", .double)
                t.column("notes", .text)
                t.column("created_at", .datetime).notNull()
            }

            // Progress Photos
            try db.create(table: "progress_photos") { t in
                t.column("id", .text).primaryKey()
                t.column("measurement_id", .text).notNull()
                    .references("measurements", onDelete: .cascade)
                t.column("photo_data", .blob).notNull()
                t.column("photo_type", .text)
                t.column("created_at", .datetime).notNull()
            }

            // Personal Records
            try db.create(table: "personal_records") { t in
                t.column("id", .text).primaryKey()
                t.column("exercise_id", .text).notNull()
                    .references("exercises", onDelete: .cascade)
                t.column("weight", .double).notNull()
                t.column("reps", .integer).notNull()
                t.column("achieved_at", .datetime).notNull()
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
            }

            // Settings
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }

            // Insert default settings
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES
                ('defaultRestTime', '90'),
                ('workoutReminderEnabled', 'false'),
                ('workoutReminderTime', '07:00'),
                ('restTimerSound', 'true'),
                ('restTimerHaptic', 'true'),
                ('weekStartsOn', '1')
            """)
        }

        return migrator
    }

    // MARK: - Generic Operations

    func read<T: FetchableRecord>(_ request: QueryInterfaceRequest<T>) throws -> [T] {
        try dbQueue.read { db in
            try request.fetchAll(db)
        }
    }

    func write<T>(_ updates: @escaping (Database) throws -> T) throws -> T {
        try dbQueue.write(updates)
    }

    // MARK: - Exercise Operations

    func fetchAllExercises() throws -> [Exercise] {
        try dbQueue.read { db in
            try Exercise.order(Exercise.Columns.name).fetchAll(db)
        }
    }

    func fetchExercise(id: UUID) throws -> Exercise? {
        try dbQueue.read { db in
            try Exercise.fetchOne(db, key: id)
        }
    }

    func saveExercise(_ exercise: Exercise) throws {
        var exercise = exercise
        exercise.updatedAt = Date()
        try dbQueue.write { db in
            try exercise.save(db)
        }
    }

    func deleteExercise(_ exercise: Exercise) throws {
        try dbQueue.write { db in
            try exercise.delete(db)
        }
    }

    func searchExercises(query: String, muscleGroup: String? = nil) throws -> [Exercise] {
        try dbQueue.read { db in
            var sql = "SELECT * FROM exercises WHERE name LIKE ?"
            var arguments: [DatabaseValueConvertible] = ["%\(query)%"]

            if let muscleGroup = muscleGroup {
                sql += " AND muscle_groups LIKE ?"
                arguments.append("%\(muscleGroup)%")
            }

            sql += " ORDER BY name"

            return try Exercise.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    // MARK: - Template Operations

    func fetchAllTemplates() throws -> [WorkoutTemplate] {
        try dbQueue.read { db in
            try WorkoutTemplate.order(WorkoutTemplate.Columns.name).fetchAll(db)
        }
    }

    func fetchTemplate(id: UUID) throws -> WorkoutTemplate? {
        try dbQueue.read { db in
            try WorkoutTemplate.fetchOne(db, key: id)
        }
    }

    func fetchTemplateWithExercises(id: UUID) throws -> TemplateWithExercises? {
        try dbQueue.read { db in
            guard let template = try WorkoutTemplate.fetchOne(db, key: id) else {
                return nil
            }

            let templateExercises = try TemplateExercise
                .filter(TemplateExercise.Columns.templateId == id)
                .order(TemplateExercise.Columns.sortOrder)
                .fetchAll(db)

            var exerciseDetails: [TemplateExerciseDetail] = []
            for te in templateExercises {
                if let exercise = try Exercise.fetchOne(db, key: te.exerciseId) {
                    exerciseDetails.append(TemplateExerciseDetail(templateExercise: te, exercise: exercise))
                }
            }

            return TemplateWithExercises(template: template, exercises: exerciseDetails)
        }
    }

    func saveTemplate(_ template: WorkoutTemplate) throws {
        var template = template
        template.updatedAt = Date()
        try dbQueue.write { db in
            try template.save(db)
        }
    }

    func deleteTemplate(_ template: WorkoutTemplate) throws {
        try dbQueue.write { db in
            try template.delete(db)
        }
    }

    func saveTemplateExercise(_ templateExercise: TemplateExercise) throws {
        try dbQueue.write { db in
            try templateExercise.save(db)
        }
    }

    func deleteTemplateExercise(_ templateExercise: TemplateExercise) throws {
        try dbQueue.write { db in
            try templateExercise.delete(db)
        }
    }

    func fetchTemplateExercises(templateId: UUID) throws -> [TemplateExerciseDetail] {
        try dbQueue.read { db in
            let templateExercises = try TemplateExercise
                .filter(TemplateExercise.Columns.templateId == templateId)
                .order(TemplateExercise.Columns.sortOrder)
                .fetchAll(db)

            var details: [TemplateExerciseDetail] = []
            for te in templateExercises {
                if let exercise = try Exercise.fetchOne(db, key: te.exerciseId) {
                    details.append(TemplateExerciseDetail(templateExercise: te, exercise: exercise))
                }
            }
            return details
        }
    }

    // MARK: - Schedule Operations

    func fetchSchedule() throws -> [Schedule] {
        try dbQueue.read { db in
            try Schedule.order(Schedule.Columns.dayOfWeek).fetchAll(db)
        }
    }

    func fetchScheduleWithTemplates() throws -> [ScheduleDay] {
        try dbQueue.read { db in
            var scheduleDays: [ScheduleDay] = []

            for day in 0..<7 {
                let schedule = try Schedule
                    .filter(Schedule.Columns.dayOfWeek == day)
                    .fetchOne(db)

                var template: WorkoutTemplate? = nil
                if let templateId = schedule?.templateId {
                    template = try WorkoutTemplate.fetchOne(db, key: templateId)
                }

                scheduleDays.append(ScheduleDay(
                    schedule: schedule,
                    template: template,
                    dayOfWeek: day
                ))
            }

            return scheduleDays
        }
    }

    func saveSchedule(_ schedule: Schedule) throws {
        try dbQueue.write { db in
            // Delete existing schedule for this day
            try Schedule
                .filter(Schedule.Columns.dayOfWeek == schedule.dayOfWeek)
                .deleteAll(db)
            // Save new schedule
            try schedule.save(db)
        }
    }

    // MARK: - Workout Session Operations

    func fetchAllSessions() throws -> [WorkoutSession] {
        try dbQueue.read { db in
            try WorkoutSession
                .order(WorkoutSession.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }

    func fetchSession(id: UUID) throws -> WorkoutSession? {
        try dbQueue.read { db in
            try WorkoutSession.fetchOne(db, key: id)
        }
    }

    func fetchSessionWithDetails(id: UUID) throws -> SessionWithDetails? {
        try dbQueue.read { db in
            guard let session = try WorkoutSession.fetchOne(db, key: id) else {
                return nil
            }

            var template: WorkoutTemplate? = nil
            if let templateId = session.templateId {
                template = try WorkoutTemplate.fetchOne(db, key: templateId)
            }

            let sets = try SessionSet
                .filter(SessionSet.Columns.sessionId == id)
                .order(SessionSet.Columns.completedAt)
                .fetchAll(db)

            var setsWithExercises: [SessionSetWithExercise] = []
            for set in sets {
                if let exercise = try Exercise.fetchOne(db, key: set.exerciseId) {
                    setsWithExercises.append(SessionSetWithExercise(set: set, exercise: exercise))
                }
            }

            let cardioSessions = try CardioSession
                .filter(CardioSession.Columns.sessionId == id)
                .fetchAll(db)

            return SessionWithDetails(
                session: session,
                template: template,
                sets: setsWithExercises,
                cardioSessions: cardioSessions
            )
        }
    }

    func saveSession(_ session: WorkoutSession) throws {
        try dbQueue.write { db in
            try session.save(db)
        }
    }

    func deleteSession(_ session: WorkoutSession) throws {
        try dbQueue.write { db in
            try session.delete(db)
        }
    }

    func fetchRecentSessions(limit: Int = 10) throws -> [SessionWithDetails] {
        try dbQueue.read { db in
            let sessions = try WorkoutSession
                .filter(WorkoutSession.Columns.completedAt != nil)
                .order(WorkoutSession.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)

            var results: [SessionWithDetails] = []
            for session in sessions {
                var template: WorkoutTemplate? = nil
                if let templateId = session.templateId {
                    template = try WorkoutTemplate.fetchOne(db, key: templateId)
                }

                let sets = try SessionSet
                    .filter(SessionSet.Columns.sessionId == session.id)
                    .fetchAll(db)

                var setsWithExercises: [SessionSetWithExercise] = []
                for set in sets {
                    if let exercise = try Exercise.fetchOne(db, key: set.exerciseId) {
                        setsWithExercises.append(SessionSetWithExercise(set: set, exercise: exercise))
                    }
                }

                let cardioSessions = try CardioSession
                    .filter(CardioSession.Columns.sessionId == session.id)
                    .fetchAll(db)

                results.append(SessionWithDetails(
                    session: session,
                    template: template,
                    sets: setsWithExercises,
                    cardioSessions: cardioSessions
                ))
            }
            return results
        }
    }

    // MARK: - Session Set Operations

    func saveSessionSet(_ set: SessionSet) throws {
        try dbQueue.write { db in
            try set.save(db)
        }
    }

    func deleteSessionSet(_ set: SessionSet) throws {
        try dbQueue.write { db in
            try set.delete(db)
        }
    }

    func fetchSessionSets(sessionId: UUID) throws -> [SessionSetWithExercise] {
        try dbQueue.read { db in
            let sets = try SessionSet
                .filter(SessionSet.Columns.sessionId == sessionId)
                .order(SessionSet.Columns.completedAt)
                .fetchAll(db)

            var results: [SessionSetWithExercise] = []
            for set in sets {
                if let exercise = try Exercise.fetchOne(db, key: set.exerciseId) {
                    results.append(SessionSetWithExercise(set: set, exercise: exercise))
                }
            }
            return results
        }
    }

    // MARK: - Cardio Session Operations

    func saveCardioSession(_ cardio: CardioSession) throws {
        try dbQueue.write { db in
            try cardio.save(db)
        }
    }

    func deleteCardioSession(_ cardio: CardioSession) throws {
        try dbQueue.write { db in
            try cardio.delete(db)
        }
    }

    // MARK: - Measurement Operations

    func fetchAllMeasurements() throws -> [Measurement] {
        try dbQueue.read { db in
            try Measurement.order(Measurement.Columns.date.desc).fetchAll(db)
        }
    }

    func fetchMeasurement(id: UUID) throws -> Measurement? {
        try dbQueue.read { db in
            try Measurement.fetchOne(db, key: id)
        }
    }

    func fetchMeasurementWithPhotos(id: UUID) throws -> MeasurementWithPhotos? {
        try dbQueue.read { db in
            guard let measurement = try Measurement.fetchOne(db, key: id) else {
                return nil
            }

            let photos = try ProgressPhoto
                .filter(ProgressPhoto.Columns.measurementId == id)
                .fetchAll(db)

            return MeasurementWithPhotos(measurement: measurement, photos: photos)
        }
    }

    func saveMeasurement(_ measurement: Measurement) throws {
        try dbQueue.write { db in
            try measurement.save(db)
        }
    }

    func deleteMeasurement(_ measurement: Measurement) throws {
        try dbQueue.write { db in
            try measurement.delete(db)
        }
    }

    // MARK: - Progress Photo Operations

    func saveProgressPhoto(_ photo: ProgressPhoto) throws {
        try dbQueue.write { db in
            try photo.save(db)
        }
    }

    func deleteProgressPhoto(_ photo: ProgressPhoto) throws {
        try dbQueue.write { db in
            try photo.delete(db)
        }
    }

    func fetchPhotos(measurementId: UUID) throws -> [ProgressPhoto] {
        try dbQueue.read { db in
            try ProgressPhoto
                .filter(ProgressPhoto.Columns.measurementId == measurementId)
                .fetchAll(db)
        }
    }

    // MARK: - Personal Record Operations

    func fetchAllPersonalRecords() throws -> [PersonalRecordWithExercise] {
        try dbQueue.read { db in
            let records = try PersonalRecord
                .order(PersonalRecord.Columns.achievedAt.desc)
                .fetchAll(db)

            var results: [PersonalRecordWithExercise] = []
            for record in records {
                if let exercise = try Exercise.fetchOne(db, key: record.exerciseId) {
                    results.append(PersonalRecordWithExercise(record: record, exercise: exercise))
                }
            }
            return results
        }
    }

    func fetchPersonalRecords(exerciseId: UUID) throws -> [PersonalRecord] {
        try dbQueue.read { db in
            try PersonalRecord
                .filter(PersonalRecord.Columns.exerciseId == exerciseId)
                .order(PersonalRecord.Columns.achievedAt.desc)
                .fetchAll(db)
        }
    }

    func fetchCurrentPR(exerciseId: UUID) throws -> PersonalRecord? {
        try dbQueue.read { db in
            try PersonalRecord
                .filter(PersonalRecord.Columns.exerciseId == exerciseId)
                .order(PersonalRecord.Columns.weight.desc)
                .fetchOne(db)
        }
    }

    func savePersonalRecord(_ record: PersonalRecord) throws {
        try dbQueue.write { db in
            try record.save(db)
        }
    }

    func checkAndSaveIfPR(exerciseId: UUID, weight: Double, reps: Int, sessionId: UUID) throws -> PersonalRecord? {
        try dbQueue.write { db in
            // Fetch existing PR for this exercise
            let existingPR = try PersonalRecord
                .filter(PersonalRecord.Columns.exerciseId == exerciseId)
                .order(PersonalRecord.Columns.weight.desc)
                .fetchOne(db)

            // Check if this is a new PR
            let isNewPR: Bool
            if let existing = existingPR {
                // New PR if weight is higher, or same weight with more reps
                isNewPR = weight > existing.weight || (weight == existing.weight && reps > existing.reps)
            } else {
                // No existing PR, so this is automatically a PR
                isNewPR = true
            }

            if isNewPR {
                let newPR = PersonalRecord(
                    exerciseId: exerciseId,
                    weight: weight,
                    reps: reps,
                    sessionId: sessionId
                )
                try newPR.save(db)
                return newPR
            }

            return nil
        }
    }

    // MARK: - Settings Operations

    func fetchSettings() throws -> AppSettings {
        try dbQueue.read { db in
            let entries = try SettingEntry.fetchAll(db)
            var settings = AppSettings()

            for entry in entries {
                switch entry.key {
                case AppSettings.defaultRestTimeKey:
                    settings.defaultRestTime = Int(entry.value) ?? 90
                case AppSettings.workoutReminderEnabledKey:
                    settings.workoutReminderEnabled = entry.value == "true"
                case AppSettings.workoutReminderTimeKey:
                    let components = entry.value.split(separator: ":")
                    if components.count == 2,
                       let hour = Int(components[0]),
                       let minute = Int(components[1]) {
                        settings.workoutReminderTime = Calendar.current.date(
                            from: DateComponents(hour: hour, minute: minute)
                        ) ?? settings.workoutReminderTime
                    }
                case AppSettings.restTimerSoundKey:
                    settings.restTimerSound = entry.value == "true"
                case AppSettings.restTimerHapticKey:
                    settings.restTimerHaptic = entry.value == "true"
                case AppSettings.weekStartsOnKey:
                    settings.weekStartsOn = Int(entry.value) ?? 1
                default:
                    break
                }
            }

            return settings
        }
    }

    func saveSetting(key: String, value: String) throws {
        try dbQueue.write { db in
            let entry = SettingEntry(key: key, value: value)
            try entry.save(db)
        }
    }

    func saveSettings(_ settings: AppSettings) throws {
        try dbQueue.write { db in
            try SettingEntry(key: AppSettings.defaultRestTimeKey, value: "\(settings.defaultRestTime)").save(db)
            try SettingEntry(key: AppSettings.workoutReminderEnabledKey, value: settings.workoutReminderEnabled ? "true" : "false").save(db)

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            try SettingEntry(key: AppSettings.workoutReminderTimeKey, value: formatter.string(from: settings.workoutReminderTime)).save(db)

            try SettingEntry(key: AppSettings.restTimerSoundKey, value: settings.restTimerSound ? "true" : "false").save(db)
            try SettingEntry(key: AppSettings.restTimerHapticKey, value: settings.restTimerHaptic ? "true" : "false").save(db)
            try SettingEntry(key: AppSettings.weekStartsOnKey, value: "\(settings.weekStartsOn)").save(db)
        }
    }

    // MARK: - Chart Data Operations

    func fetchExerciseProgress(exerciseId: UUID, from startDate: Date? = nil, to endDate: Date? = nil) throws -> [(date: Date, maxWeight: Double, totalVolume: Double)] {
        try dbQueue.read { db in
            var sql = """
                SELECT DATE(ss.completed_at) as date,
                       MAX(ss.weight) as max_weight,
                       SUM(COALESCE(ss.reps, 0) * COALESCE(ss.weight, 0)) as total_volume
                FROM session_sets ss
                WHERE ss.exercise_id = ?
            """
            var arguments: [DatabaseValueConvertible] = [exerciseId]

            if let start = startDate {
                sql += " AND ss.completed_at >= ?"
                arguments.append(start)
            }
            if let end = endDate {
                sql += " AND ss.completed_at <= ?"
                arguments.append(end)
            }

            sql += " GROUP BY DATE(ss.completed_at) ORDER BY date"

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.compactMap { row -> (Date, Double, Double)? in
                guard let dateString: String = row["date"],
                      let date = ISO8601DateFormatter().date(from: dateString + "T00:00:00Z") else {
                    return nil
                }
                let maxWeight: Double = row["max_weight"] ?? 0
                let totalVolume: Double = row["total_volume"] ?? 0
                return (date, maxWeight, totalVolume)
            }
        }
    }

    func fetchBodyWeightProgress(from startDate: Date? = nil, to endDate: Date? = nil) throws -> [(date: Date, weight: Double)] {
        try dbQueue.read { db in
            var request = Measurement
                .filter(Measurement.Columns.bodyWeight != nil)
                .order(Measurement.Columns.date)

            if let start = startDate {
                request = request.filter(Measurement.Columns.date >= start)
            }
            if let end = endDate {
                request = request.filter(Measurement.Columns.date <= end)
            }

            let measurements = try request.fetchAll(db)
            return measurements.compactMap { m -> (Date, Double)? in
                guard let weight = m.bodyWeight else { return nil }
                return (m.date, weight)
            }
        }
    }

    // MARK: - Export Operations

    func exportToJSON() throws -> Data {
        try dbQueue.read { db in
            var export: [String: Any] = [:]

            let exercises = try Exercise.fetchAll(db)
            export["exercises"] = exercises.map { e -> [String: Any] in
                [
                    "id": e.id.uuidString,
                    "name": e.name,
                    "exerciseType": e.exerciseType.rawValue,
                    "muscleGroups": e.muscleGroups,
                    "equipment": e.equipment as Any,
                    "notes": e.notes as Any,
                    "createdAt": ISO8601DateFormatter().string(from: e.createdAt),
                    "updatedAt": ISO8601DateFormatter().string(from: e.updatedAt)
                ]
            }

            let templates = try WorkoutTemplate.fetchAll(db)
            export["templates"] = templates.map { t -> [String: Any] in
                [
                    "id": t.id.uuidString,
                    "name": t.name,
                    "createdAt": ISO8601DateFormatter().string(from: t.createdAt),
                    "updatedAt": ISO8601DateFormatter().string(from: t.updatedAt)
                ]
            }

            let sessions = try WorkoutSession.fetchAll(db)
            export["workoutSessions"] = sessions.map { s -> [String: Any] in
                [
                    "id": s.id.uuidString,
                    "templateId": s.templateId?.uuidString as Any,
                    "startedAt": ISO8601DateFormatter().string(from: s.startedAt),
                    "completedAt": s.completedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
                    "duration": s.duration as Any,
                    "notes": s.notes as Any
                ]
            }

            let sets = try SessionSet.fetchAll(db)
            export["sessionSets"] = sets.map { s -> [String: Any] in
                [
                    "id": s.id.uuidString,
                    "sessionId": s.sessionId.uuidString,
                    "exerciseId": s.exerciseId.uuidString,
                    "setNumber": s.setNumber,
                    "reps": s.reps as Any,
                    "duration": s.duration as Any,
                    "weight": s.weight as Any,
                    "completedAt": ISO8601DateFormatter().string(from: s.completedAt)
                ]
            }

            let measurements = try Measurement.fetchAll(db)
            export["measurements"] = measurements.map { m -> [String: Any] in
                [
                    "id": m.id.uuidString,
                    "date": ISO8601DateFormatter().string(from: m.date),
                    "bodyWeight": m.bodyWeight as Any,
                    "bodyFat": m.bodyFat as Any,
                    "notes": m.notes as Any,
                    "createdAt": ISO8601DateFormatter().string(from: m.createdAt)
                ]
            }

            let records = try PersonalRecord.fetchAll(db)
            export["personalRecords"] = records.map { r -> [String: Any] in
                [
                    "id": r.id.uuidString,
                    "exerciseId": r.exerciseId.uuidString,
                    "weight": r.weight,
                    "reps": r.reps,
                    "achievedAt": ISO8601DateFormatter().string(from: r.achievedAt),
                    "sessionId": r.sessionId.uuidString
                ]
            }

            return try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
        }
    }

    func exportToCSV() throws -> [String: String] {
        try dbQueue.read { db in
            var csvFiles: [String: String] = [:]

            // Exercises CSV
            let exercises = try Exercise.fetchAll(db)
            var exerciseCSV = "id,name,exercise_type,muscle_groups,equipment,notes,created_at,updated_at\n"
            for e in exercises {
                exerciseCSV += "\"\(e.id.uuidString)\",\"\(e.name)\",\"\(e.exerciseType.rawValue)\",\"\(e.muscleGroups.joined(separator: ";"))\",\"\(e.equipment ?? "")\",\"\(e.notes ?? "")\",\"\(e.createdAt)\",\"\(e.updatedAt)\"\n"
            }
            csvFiles["exercises.csv"] = exerciseCSV

            // Sessions CSV
            let sessions = try WorkoutSession.fetchAll(db)
            var sessionCSV = "id,template_id,started_at,completed_at,duration,notes\n"
            for s in sessions {
                sessionCSV += "\"\(s.id.uuidString)\",\"\(s.templateId?.uuidString ?? "")\",\"\(s.startedAt)\",\"\(s.completedAt?.description ?? "")\",\"\(s.duration ?? 0)\",\"\(s.notes ?? "")\"\n"
            }
            csvFiles["workout_sessions.csv"] = sessionCSV

            // Sets CSV
            let sets = try SessionSet.fetchAll(db)
            var setsCSV = "id,session_id,exercise_id,set_number,reps,duration,weight,completed_at\n"
            for s in sets {
                setsCSV += "\"\(s.id.uuidString)\",\"\(s.sessionId.uuidString)\",\"\(s.exerciseId.uuidString)\",\(s.setNumber),\(s.reps ?? 0),\(s.duration ?? 0),\(s.weight ?? 0),\"\(s.completedAt)\"\n"
            }
            csvFiles["session_sets.csv"] = setsCSV

            // Measurements CSV
            let measurements = try Measurement.fetchAll(db)
            var measurementCSV = "id,date,body_weight,body_fat,neck,shoulders,chest,waist,hips,notes,created_at\n"
            for m in measurements {
                measurementCSV += "\"\(m.id.uuidString)\",\"\(m.date)\",\(m.bodyWeight ?? 0),\(m.bodyFat ?? 0),\(m.neck ?? 0),\(m.shoulders ?? 0),\(m.chest ?? 0),\(m.waist ?? 0),\(m.hips ?? 0),\"\(m.notes ?? "")\",\"\(m.createdAt)\"\n"
            }
            csvFiles["measurements.csv"] = measurementCSV

            return csvFiles
        }
    }
}
