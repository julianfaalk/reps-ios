import XCTest
@testable import REPSCore

final class WorkoutPlannerTests: XCTestCase {
    private var db: DatabaseService!
    private var generator: WorkoutPlanGenerator!

    override func setUpWithError() throws {
        db = DatabaseService(inMemory: true)
        generator = WorkoutPlanGenerator()
    }

    override func tearDownWithError() throws {
        db = nil
        generator = nil
    }

    @MainActor
    func testTodayViewModelRespectsWeekStartsOnAndMonthSummaries() async throws {
        let template = try template(named: "Push (Brust, Trizeps, vordere Schulter)")
        let sessionDate = makeDate(year: 2026, month: 2, day: 1, hour: 10)
        try db.saveSession(
            WorkoutSession(
                templateId: template.id,
                startedAt: sessionDate,
                completedAt: sessionDate.addingTimeInterval(3600),
                duration: 3600
            )
        )

        var settings = try db.fetchSettings()
        settings.weekStartsOn = 0
        try db.saveSettings(settings)

        let sundayViewModel = TodayViewModel(db: db, referenceDate: sessionDate)
        await sundayViewModel.refresh()
        XCTAssertEqual(sundayViewModel.weekdaySymbols.first, Calendar.current.shortWeekdaySymbols[0])
        XCTAssertTrue(sundayViewModel.hasCompletedWorkout(on: sessionDate))

        settings.weekStartsOn = 1
        try db.saveSettings(settings)

        let mondayViewModel = TodayViewModel(db: db, referenceDate: sessionDate)
        await mondayViewModel.refresh()
        XCTAssertEqual(mondayViewModel.weekdaySymbols.first, Calendar.current.shortWeekdaySymbols[1])
        XCTAssertTrue(mondayViewModel.monthSummaries.keys.contains(Calendar.current.startOfDay(for: sessionDate)))
    }

    func testFetchCompletedSessionsReturnsAllSessionsForDay() throws {
        let template = try template(named: "Pull (Rücken, Bizeps, hintere Schulter)")
        let date = makeDate(year: 2026, month: 3, day: 3, hour: 8)
        try db.saveSession(
            WorkoutSession(
                templateId: template.id,
                startedAt: date,
                completedAt: date.addingTimeInterval(1800),
                duration: 1800
            )
        )
        try db.saveSession(
            WorkoutSession(
                templateId: template.id,
                startedAt: date.addingTimeInterval(3600),
                completedAt: date.addingTimeInterval(5400),
                duration: 1800
            )
        )

        let sessions = try db.fetchCompletedSessions(on: date)
        XCTAssertEqual(sessions.count, 2)
    }

    func testBuiltInGeneratorKeepsAnchorsAndChangesNonAnchors() throws {
        let template = try template(named: "Push (Brust, Trizeps, vordere Schulter)")
        let baseExercises = try db.fetchTemplateExercises(templateId: template.id)
        let allExercises = try db.fetchAllExercises()

        let firstPlan = try generator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: nil,
            shuffleSeed: 0
        )
        let secondPlan = try generator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: firstPlan.exercises.map {
                WorkoutPlanExerciseSnapshot(exercise: $0.exercise, sortOrder: $0.sortOrder, isAnchor: $0.isAnchor)
            },
            shuffleSeed: 1
        )

        let anchorGroups = Set(secondPlan.exercises.filter(\.isAnchor).compactMap(\.exercise.variationGroup))
        XCTAssertTrue(anchorGroups.contains("bench-press"))
        XCTAssertTrue(anchorGroups.contains("push-up"))

        for (lhs, rhs) in zip(firstPlan.exercises, secondPlan.exercises) where lhs.isAnchor == false && rhs.isAnchor == false {
            XCTAssertNotEqual(lhs.exercise.variationGroup, rhs.exercise.variationGroup)
        }
    }

    func testCustomGeneratorPreservesFirstTwoCompoundAnchorsAndKeepsCompatibility() throws {
        let exercises = try namedExercises([
            "Bankdrücken",
            "Rudern Langhantel",
            "Cable Flys",
            "Trizeps Pushdowns"
        ])

        let template = WorkoutTemplate(name: "Upper Chaos")
        let baseExercises = exercises.enumerated().map { index, exercise in
            TemplateExerciseDetail(
                templateExercise: TemplateExercise(
                    templateId: template.id,
                    exerciseId: exercise.id,
                    sortOrder: index,
                    targetSets: 3,
                    targetReps: 10
                ),
                exercise: exercise
            )
        }

        let result = try generator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: try db.fetchAllExercises(),
            previousPlan: nil,
            shuffleSeed: 3
        )

        XCTAssertEqual(result.exercises[0].exercise.id, exercises[0].id)
        XCTAssertEqual(result.exercises[1].exercise.id, exercises[1].id)

        for index in 2..<result.exercises.count {
            let baseMuscles = Set(baseExercises[index].exercise.muscleGroups)
            let newMuscles = Set(result.exercises[index].exercise.muscleGroups)
            XCTAssertFalse(baseMuscles.isDisjoint(with: newMuscles))
        }
    }

    func testSavingShuffledDayPlanDoesNotMutateTemplateExercises() throws {
        let template = try template(named: "Legs (Beine, unterer Rücken)")
        let baseExercises = try db.fetchTemplateExercises(templateId: template.id)
        let templateExerciseIDs = baseExercises.map(\.exercise.id)
        let allExercises = try db.fetchAllExercises()

        let firstBuild = try generator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: nil,
            shuffleSeed: 0
        )
        let savedPlan = try db.saveWorkoutDayPlan(
            date: makeDate(year: 2026, month: 3, day: 5, hour: 7),
            template: template,
            exercises: firstBuild.exercises,
            shuffleCount: 0
        )

        let shuffledBuild = try generator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: savedPlan.exercises.map {
                WorkoutPlanExerciseSnapshot(exercise: $0.exercise, sortOrder: $0.planExercise.sortOrder, isAnchor: $0.planExercise.isAnchor)
            },
            shuffleSeed: 1
        )

        let updatedPlan = try db.saveWorkoutDayPlan(
            date: savedPlan.plan.date,
            template: template,
            exercises: shuffledBuild.exercises,
            shuffleCount: 1,
            existingPlanId: savedPlan.plan.id
        )

        XCTAssertEqual(updatedPlan.plan.id, savedPlan.plan.id)
        XCTAssertEqual(try db.fetchTemplateExercises(templateId: template.id).map(\.exercise.id), templateExerciseIDs)
    }

    @MainActor
    func testWorkoutSessionStartsFromSavedDayPlanSnapshot() async throws {
        let template = try template(named: "Schultern, Arme & Core")
        let baseExercises = try db.fetchTemplateExercises(templateId: template.id)
        let build = try generator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: try db.fetchAllExercises(),
            previousPlan: nil,
            shuffleSeed: 0
        )
        let savedPlan = try db.saveWorkoutDayPlan(
            date: makeDate(year: 2026, month: 3, day: 6, hour: 7),
            template: template,
            exercises: build.exercises,
            shuffleCount: 0
        )

        let viewModel = WorkoutViewModel(db: db)
        await viewModel.startSession(dayPlan: savedPlan)

        XCTAssertEqual(viewModel.currentSession?.dayPlanId, savedPlan.plan.id)
        XCTAssertEqual(viewModel.templateExercises.map(\.exercise.id), savedPlan.exercises.map(\.exercise.id))
    }

    @MainActor
    func testTodayViewModelLoadsCompletedSessionsForToday() async throws {
        let template = try template(named: "Push (Brust, Trizeps, vordere Schulter)")
        let date = makeDate(year: 2026, month: 3, day: 17, hour: 15)

        try db.saveSession(
            WorkoutSession(
                templateId: template.id,
                startedAt: date,
                completedAt: date.addingTimeInterval(2700),
                duration: 2700
            )
        )

        let viewModel = TodayViewModel(db: db, referenceDate: date)
        await viewModel.refresh()

        XCTAssertTrue(viewModel.hasCompletedWorkoutToday)
        XCTAssertEqual(viewModel.todayCompletedSessions.count, 1)
        XCTAssertEqual(viewModel.todayCompletedSessions.first?.template?.id, template.id)
    }

    @MainActor
    func testShuffleIsBlockedAfterFirstLoggedSet() async throws {
        let template = try template(named: "Push (Brust, Trizeps, vordere Schulter)")
        let build = try generator.buildPlan(
            template: template,
            baseExercises: try db.fetchTemplateExercises(templateId: template.id),
            allExercises: try db.fetchAllExercises(),
            previousPlan: nil,
            shuffleSeed: 0
        )
        let savedPlan = try db.saveWorkoutDayPlan(
            date: makeDate(year: 2026, month: 3, day: 6, hour: 9),
            template: template,
            exercises: build.exercises,
            shuffleCount: 0
        )

        let viewModel = WorkoutViewModel(db: db)
        await viewModel.startSession(dayPlan: savedPlan)
        await viewModel.addWarmupCardio(type: .bike)
        await viewModel.logSet(reps: 8, duration: nil, weight: 60)

        let message = await viewModel.shuffleCurrentWorkout()
        XCTAssertEqual(message, "Shuffle is only available before you log the first set.")
    }

    @MainActor
    func testPreviewPlanLoadsFutureScheduledWorkoutWithoutPersistingIt() async throws {
        let template = try template(named: "Push (Brust, Trizeps, vordere Schulter)")
        let scheduleDay = try scheduledDay(for: template.id)
        let referenceDate = makeDate(year: 2026, month: 3, day: 17, hour: 9)
        let futureDate = nextDate(after: referenceDate, matchingScheduleDay: scheduleDay.dayOfWeek)

        XCTAssertNil(try db.fetchWorkoutDayPlan(date: futureDate, templateId: template.id))

        let viewModel = TodayViewModel(db: db, referenceDate: referenceDate)
        await viewModel.refresh()

        let preview = await viewModel.previewPlan(for: futureDate)

        XCTAssertEqual(preview?.plan.template.id, template.id)
        XCTAssertFalse(preview?.isPersistedPlan ?? true)
        XCTAssertNil(try db.fetchWorkoutDayPlan(date: futureDate, templateId: template.id))
    }

    @MainActor
    func testBalancedRotationReusesPreviousPlanForNextTemplateSession() async throws {
        let template = try template(named: "Push (Brust, Trizeps, vordere Schulter)")
        let scheduleDay = try scheduledDay(for: template.id)
        let referenceDate = makeDate(year: 2026, month: 3, day: 17, hour: 9)
        let nextScheduledDate = nextDate(after: referenceDate, matchingScheduleDay: scheduleDay.dayOfWeek)
        let previousScheduledDate = Calendar.current.date(byAdding: .day, value: -7, to: nextScheduledDate) ?? nextScheduledDate

        var settings = try db.fetchSettings()
        settings.rotationStyleValue = .balanced
        try db.saveSettings(settings)

        let previousBuild = try generator.buildPlan(
            template: template,
            baseExercises: try db.fetchTemplateExercises(templateId: template.id),
            allExercises: try db.fetchAllExercises(),
            previousPlan: nil,
            shuffleSeed: 0
        )
        let savedPlan = try db.saveWorkoutDayPlan(
            date: previousScheduledDate,
            template: template,
            exercises: previousBuild.exercises,
            shuffleCount: 0
        )
        try db.saveSession(
            WorkoutSession(
                templateId: template.id,
                dayPlanId: savedPlan.plan.id,
                startedAt: previousScheduledDate.addingTimeInterval(60 * 60 * 12),
                completedAt: previousScheduledDate.addingTimeInterval(60 * 60 * 13),
                duration: 3600
            )
        )

        let viewModel = TodayViewModel(db: db, referenceDate: referenceDate)
        await viewModel.refresh()

        let preview = await viewModel.previewPlan(for: nextScheduledDate)

        XCTAssertTrue(preview?.isReusedBlock ?? false)
        XCTAssertEqual(
            preview?.plan.exercises.map(\.exercise.id),
            savedPlan.exercises.map(\.exercise.id)
        )
    }

    func testExportJSONRoundTripRestoresCompleteBackup() throws {
        let customExercise = Exercise(
            name: "Machine Row Neutral Grip",
            exerciseType: .reps,
            muscleGroups: ["Back"],
            equipment: "Machine",
            notes: "Custom migration test exercise"
        )
        try db.saveExercise(customExercise)

        let customTemplate = WorkoutTemplate(name: "Custom Pull Day")
        try db.saveTemplate(customTemplate)
        try db.saveTemplateExercise(
            TemplateExercise(
                templateId: customTemplate.id,
                exerciseId: customExercise.id,
                sortOrder: 0,
                targetSets: 4,
                targetReps: 8,
                targetWeight: 72.5
            )
        )

        let planDate = makeDate(year: 2026, month: 3, day: 25, hour: 18)
        let savedPlan = try db.saveWorkoutDayPlan(
            date: planDate,
            template: customTemplate,
            exercises: [
                WorkoutPlanExerciseDraft(
                    exercise: customExercise,
                    sortOrder: 0,
                    targetSets: 4,
                    targetReps: 8,
                    targetDuration: nil,
                    targetWeight: 72.5,
                    isAnchor: true
                )
            ],
            shuffleCount: 0
        )

        let sessionStart = planDate.addingTimeInterval(300)
        let session = WorkoutSession(
            templateId: customTemplate.id,
            dayPlanId: savedPlan.plan.id,
            startedAt: sessionStart,
            completedAt: sessionStart.addingTimeInterval(3000),
            duration: 3000,
            notes: "Migration roundtrip session"
        )
        try db.saveSession(session)
        try db.saveSessionSet(
            SessionSet(
                sessionId: session.id,
                exerciseId: customExercise.id,
                setNumber: 1,
                reps: 8,
                weight: 72.5,
                completedAt: sessionStart.addingTimeInterval(600)
            )
        )
        try db.saveCardioSession(
            CardioSession(
                sessionId: session.id,
                cardioType: .bike,
                duration: 600,
                calories: 110,
                notes: "Warmup"
            )
        )

        let measurement = Measurement(
            date: makeDate(year: 2026, month: 3, day: 24, hour: 8),
            bodyWeight: 82.4,
            bodyFat: 14.1,
            notes: "Check-in"
        )
        try db.saveMeasurement(measurement)
        try db.saveProgressPhoto(
            ProgressPhoto(
                measurementId: measurement.id,
                photoData: Data([0x01, 0x02, 0x03]),
                photoType: .front,
                createdAt: measurement.createdAt
            )
        )
        try db.savePersonalRecord(
            PersonalRecord(
                exerciseId: customExercise.id,
                weight: 72.5,
                reps: 8,
                achievedAt: sessionStart.addingTimeInterval(600),
                sessionId: session.id
            )
        )

        var settings = try db.fetchSettings()
        settings.weekStartsOn = 0
        settings.trainingSetupCompleted = true
        settings.preferredLanguage = AppLanguage.german.rawValue
        try db.saveSettings(settings)

        let backupData = try db.exportToJSON()

        let restoredDB = DatabaseService(inMemory: true)
        let summary = try restoredDB.importFromJSON(backupData)

        XCTAssertEqual(summary.source, "reps_backup")
        XCTAssertEqual(summary.workoutSessions, 1)
        XCTAssertEqual(summary.measurements, 1)
        XCTAssertEqual(try restoredDB.fetchAllSessions().count, 1)
        XCTAssertEqual(try restoredDB.fetchAllMeasurements().count, 1)
        XCTAssertEqual(try restoredDB.fetchAllPersonalRecords().count, 1)
        XCTAssertEqual(try restoredDB.fetchTemplateExercises(templateId: customTemplate.id).count, 1)
        XCTAssertEqual(try restoredDB.read(CardioSession.all()).count, 1)
        XCTAssertEqual(try restoredDB.fetchWorkoutDayPlan(id: savedPlan.plan.id)?.exercises.first?.exercise.id, customExercise.id)
        XCTAssertEqual(try restoredDB.fetchMeasurementWithPhotos(id: measurement.id)?.photos.count, 1)
        XCTAssertEqual(try restoredDB.fetchSession(id: session.id)?.dayPlanId, savedPlan.plan.id)

        let restoredSettings = try restoredDB.fetchSettings()
        XCTAssertEqual(restoredSettings.weekStartsOn, 0)
        XCTAssertEqual(restoredSettings.preferredLanguage, AppLanguage.german.rawValue)
    }

    func testLegacyExportImportMapsKnownExercisesToCurrentCatalog() throws {
        let now = makeDate(year: 2026, month: 3, day: 26, hour: 10)
        let knownExerciseID = UUID()
        let customExerciseID = UUID()
        let knownTemplateID = UUID()
        let customTemplateID = UUID()
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let firstSetID = UUID()
        let secondSetID = UUID()
        let measurementID = UUID()
        let recordID = UUID()

        let legacyJSON = """
        {
          "exercises": [
            {
              "id": "\(knownExerciseID.uuidString)",
              "name": "Bankdrücken",
              "exerciseType": "reps",
              "muscleGroups": ["Chest", "Triceps"],
              "equipment": "Barbell",
              "notes": "Legacy known exercise",
              "createdAt": "\(isoString(now))",
              "updatedAt": "\(isoString(now))"
            },
            {
              "id": "\(customExerciseID.uuidString)",
              "name": "Seal Row",
              "exerciseType": "reps",
              "muscleGroups": ["Back"],
              "equipment": "Machine",
              "notes": "Legacy custom exercise",
              "createdAt": "\(isoString(now))",
              "updatedAt": "\(isoString(now))"
            }
          ],
          "templates": [
            {
              "id": "\(knownTemplateID.uuidString)",
              "name": "Push (Brust, Trizeps, vordere Schulter)",
              "createdAt": "\(isoString(now))",
              "updatedAt": "\(isoString(now))"
            },
            {
              "id": "\(customTemplateID.uuidString)",
              "name": "Custom Volume Day",
              "createdAt": "\(isoString(now))",
              "updatedAt": "\(isoString(now))"
            }
          ],
          "workoutSessions": [
            {
              "id": "\(firstSessionID.uuidString)",
              "templateId": "\(knownTemplateID.uuidString)",
              "startedAt": "\(isoString(now))",
              "completedAt": "\(isoString(now.addingTimeInterval(1800)))",
              "duration": 1800,
              "notes": "Legacy push workout"
            },
            {
              "id": "\(secondSessionID.uuidString)",
              "templateId": "\(customTemplateID.uuidString)",
              "startedAt": "\(isoString(now.addingTimeInterval(3600)))",
              "completedAt": "\(isoString(now.addingTimeInterval(5400)))",
              "duration": 1800,
              "notes": "Legacy custom workout"
            }
          ],
          "sessionSets": [
            {
              "id": "\(firstSetID.uuidString)",
              "sessionId": "\(firstSessionID.uuidString)",
              "exerciseId": "\(knownExerciseID.uuidString)",
              "setNumber": 1,
              "reps": 8,
              "duration": null,
              "weight": 80,
              "completedAt": "\(isoString(now.addingTimeInterval(600)))"
            },
            {
              "id": "\(secondSetID.uuidString)",
              "sessionId": "\(secondSessionID.uuidString)",
              "exerciseId": "\(customExerciseID.uuidString)",
              "setNumber": 1,
              "reps": 10,
              "duration": null,
              "weight": 55,
              "completedAt": "\(isoString(now.addingTimeInterval(4200)))"
            }
          ],
          "measurements": [
            {
              "id": "\(measurementID.uuidString)",
              "date": "\(isoString(now))",
              "bodyWeight": 81.2,
              "bodyFat": 13.4,
              "notes": "Legacy measurement",
              "createdAt": "\(isoString(now))"
            }
          ],
          "personalRecords": [
            {
              "id": "\(recordID.uuidString)",
              "exerciseId": "\(customExerciseID.uuidString)",
              "weight": 55,
              "reps": 10,
              "achievedAt": "\(isoString(now.addingTimeInterval(4200)))",
              "sessionId": "\(secondSessionID.uuidString)"
            }
          ]
        }
        """

        let restoredDB = DatabaseService(inMemory: true)
        let summary = try restoredDB.importFromJSON(Data(legacyJSON.utf8))

        XCTAssertEqual(summary.source, "legacy_export")
        XCTAssertEqual(summary.workoutSessions, 2)
        XCTAssertEqual(summary.measurements, 1)

        let allExercises = try restoredDB.fetchAllExercises()
        let knownExercise = try XCTUnwrap(allExercises.first(where: { $0.name == "Bankdrücken" }))
        let customExercise = try XCTUnwrap(allExercises.first(where: { $0.name == "Seal Row" }))

        XCTAssertNotEqual(knownExercise.id, knownExerciseID)
        XCTAssertEqual(customExercise.id, customExerciseID)

        let knownSessionSets = try restoredDB.fetchSessionSets(sessionId: firstSessionID)
        XCTAssertEqual(knownSessionSets.first?.exercise.id, knownExercise.id)

        let customSession = try restoredDB.fetchSessionWithDetails(id: secondSessionID)
        XCTAssertEqual(customSession?.template?.name, "Custom Volume Day")
        XCTAssertEqual(customSession?.sets.first?.exercise.id, customExerciseID)
        XCTAssertEqual(try restoredDB.fetchAllPersonalRecords().first?.exercise.id, customExerciseID)
    }

    private func template(named name: String) throws -> WorkoutTemplate {
        guard let template = try db.fetchAllTemplates().first(where: { $0.name == name }) else {
            throw XCTSkip("Missing seeded template \(name)")
        }
        return template
    }

    private func namedExercises(_ names: [String]) throws -> [Exercise] {
        let allExercises = try db.fetchAllExercises()
        return try names.map { name in
            guard let exercise = allExercises.first(where: { $0.name == name }) else {
                throw XCTSkip("Missing seeded exercise \(name)")
            }
            return exercise
        }
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone(identifier: "Europe/Berlin")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        return components.date ?? Date()
    }

    private func scheduledDay(for templateId: UUID) throws -> ScheduleDay {
        guard let scheduleDay = try db.fetchScheduleWithTemplates().first(where: { $0.template?.id == templateId }) else {
            throw XCTSkip("Missing seeded schedule for template \(templateId)")
        }
        return scheduleDay
    }

    private func nextDate(after start: Date, matchingScheduleDay scheduleDay: Int) -> Date {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: start)

        while (calendar.component(.weekday, from: cursor) - 1) != scheduleDay {
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        return cursor
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
