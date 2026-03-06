import XCTest
@testable import WorkoutAppCore

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
}
