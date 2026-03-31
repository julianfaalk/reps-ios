import Foundation
import SwiftUI

struct PlannedWorkoutPreview: Identifiable {
    var date: Date
    var schedule: ScheduleDay
    var plan: WorkoutDayPlanWithExercises
    var isPersistedPlan: Bool
    var isReusedBlock: Bool
    var goalFocus: TrainingGoalFocus
    var rotationStyle: WorkoutRotationStyle
    var preferredSessionLengthMinutes: Int
    var completedTemplateSessions: Int

    var id: Date { date }

    var anchorExercises: [WorkoutDayPlanExerciseDetail] {
        plan.exercises.filter(\.planExercise.isAnchor)
    }

    var accessoryExercises: [WorkoutDayPlanExerciseDetail] {
        plan.exercises.filter { !$0.planExercise.isAnchor }
    }

    var estimatedDurationMinutes: Int {
        max(35, preferredSessionLengthMinutes + max(0, plan.exercises.count - 5) * 4)
    }
}

private struct ResolvedWorkoutDayPlan {
    let plan: WorkoutDayPlanWithExercises
    let isPersisted: Bool
    let isReusedBlock: Bool
}

struct CalendarMonthDay: Identifiable, Hashable {
    var date: Date
    var isInDisplayedMonth: Bool
    var isToday: Bool
    var summary: WorkoutCalendarDaySummary?
    var isScheduledWorkout: Bool
    var isRestDay: Bool
    var isMissedWorkout: Bool

    var id: Date { date }

    var isPlannedWorkout: Bool {
        isScheduledWorkout && summary == nil && !isMissedWorkout
    }

    var hasAnyState: Bool {
        summary != nil || isScheduledWorkout || isRestDay || isMissedWorkout
    }
}

struct TodayMonthSummarySnapshot: Hashable {
    let monthTitle: String
    let activeDays: Int
    let totalWorkouts: Int
    let expectedWorkouts: Int
    let missedWorkouts: Int
    let remainingScheduledWorkouts: Int

    var consistency: Double {
        guard expectedWorkouts > 0 else { return 0 }
        return min(1, Double(activeDays) / Double(expectedWorkouts))
    }
}

struct TodayMomentumSnapshot: Hashable {
    let streakDays: Int
    let weeklySessions: Int
    let monthlyActiveDays: Int
    let monthlyWorkoutCount: Int
    let monthlyConsistency: Double
    let todayXP: Int

    var score: Int {
        (monthlyActiveDays * 120) + (monthlyWorkoutCount * 40) + (streakDays * 30) + todayXP
    }

    var level: Int {
        max(1, (score / 300) + 1)
    }

    var progressToNextLevel: Double {
        Double(score % 300) / 300
    }

    var nextLevelScore: Int {
        level * 300
    }

    var rankTitle: String {
        switch level {
        case 1...2:
            return "Starter"
        case 3...4:
            return "Locked In"
        case 5...7:
            return "On Fire"
        default:
            return "Elite"
        }
    }
}

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var todaySchedule: ScheduleDay?
    @Published var displayedMonth: Date
    @Published var weekStartsOn: Int = 1
    @Published var monthSummaries: [Date: WorkoutCalendarDaySummary] = [:]
    @Published var todayPlan: WorkoutDayPlanWithExercises?
    @Published var todayCompletedSessions: [SessionWithDetails] = []
    @Published var todayShuffleUnavailableReason: String?
    @Published var selectedDaySessions: [SessionWithDetails] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let planGenerator = WorkoutPlanGenerator()
    private let referenceToday: Date
    private var appSettings = AppSettings()
    private var scheduleDays: [ScheduleDay] = []
    private var recentCompletedSessions: [SessionWithDetails] = []

    init(db: DatabaseService = .shared, referenceDate: Date = Date()) {
        self.db = db
        self.referenceToday = referenceDate
        self.displayedMonth = TodayViewModel.startOfMonth(for: referenceDate)

        Task {
            await refresh()
        }
    }

    var today: Date {
        Calendar.current.startOfDay(for: referenceToday)
    }

    var displayedMonthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    var weekdaySymbols: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        return (0..<7).map { index in
            let symbolIndex = (weekStartsOn + index) % 7
            return symbols[symbolIndex]
        }
    }

    var monthGridDays: [CalendarMonthDay] {
        buildMonthGrid(for: displayedMonth)
    }

    var hasCompletedWorkoutToday: Bool {
        !todayCompletedSessions.isEmpty
    }

    var displayedMonthSummary: TodayMonthSummarySnapshot {
        let activeDays = monthSummaries.count
        let totalWorkouts = monthSummaries.values.reduce(0) { $0 + $1.workoutCount }
        let breakdown = workoutExpectationBreakdown(in: displayedMonth)

        return TodayMonthSummarySnapshot(
            monthTitle: displayedMonthTitle,
            activeDays: activeDays,
            totalWorkouts: totalWorkouts,
            expectedWorkouts: breakdown.expected,
            missedWorkouts: breakdown.missed,
            remainingScheduledWorkouts: breakdown.remaining
        )
    }

    var todayMomentumSnapshot: TodayMomentumSnapshot {
        let calendar = Calendar.current
        let monthStart = Self.startOfMonth(for: today)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        let uniqueMonthDays = Set(
            recentCompletedSessions
                .map { calendar.startOfDay(for: $0.session.startedAt) }
                .filter { $0 >= monthStart && $0 <= today }
        )
        let monthlySessions = recentCompletedSessions.filter {
            $0.session.startedAt >= monthStart && $0.session.startedAt <= today
        }
        let weeklySessions = recentCompletedSessions.filter { session in
            guard let weekInterval else { return false }
            return weekInterval.contains(session.session.startedAt)
        }.count
        let monthToDateExpected = expectedWorkoutCount(in: today, upTo: today)
        let todayXP = todayCompletedSessions.reduce(0) { total, session in
            total + (session.totalSets * 12) + (session.exercisesCompleted * 18) + max(24, (session.session.duration ?? 0) / 60)
        }

        return TodayMomentumSnapshot(
            streakDays: currentStreakDays,
            weeklySessions: weeklySessions,
            monthlyActiveDays: uniqueMonthDays.count,
            monthlyWorkoutCount: monthlySessions.count,
            monthlyConsistency: monthToDateExpected > 0
                ? min(1, Double(uniqueMonthDays.count) / Double(monthToDateExpected))
                : 0,
            todayXP: todayXP
        )
    }

    var currentStreakDays: Int {
        let calendar = Calendar.current
        let completedDays = Set(recentCompletedSessions.map { calendar.startOfDay(for: $0.session.startedAt) })
        guard !completedDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = hasCompletedWorkoutToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)

        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            try await loadSettingsAndSchedule()
            try await loadMonthSummaries()
            try await loadRecentCompletedSessions()
            try await loadTodayCompletedSessions()
            try await loadTodayPlan()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func showPreviousMonth() async {
        guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) else {
            return
        }
        displayedMonth = Self.startOfMonth(for: previous)
        await reloadDisplayedMonth()
    }

    func showNextMonth() async {
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) else {
            return
        }
        displayedMonth = Self.startOfMonth(for: next)
        await reloadDisplayedMonth()
    }

    func hasCompletedWorkout(on date: Date) -> Bool {
        monthSummaries[Calendar.current.startOfDay(for: date)] != nil
    }

    func loadHistory(for date: Date) async {
        do {
            selectedDaySessions = try db.fetchCompletedSessions(on: date)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewPlan(for date: Date) async -> PlannedWorkoutPreview? {
        do {
            if scheduleDays.isEmpty {
                try await loadSettingsAndSchedule()
            }

            let normalized = Calendar.current.startOfDay(for: date)
            guard let scheduledDay = scheduleDay(for: normalized),
                  scheduledDay.isRestDay == false,
                  scheduledDay.template != nil else {
                return nil
            }

            let resolved = try resolveDayPlan(for: normalized, schedule: scheduledDay, persistIfNeeded: false)
            let completedTemplateSessions = try db.fetchCompletedSessionCount(
                templateId: resolved.plan.template.id,
                before: normalized
            )

            return PlannedWorkoutPreview(
                date: normalized,
                schedule: scheduledDay,
                plan: resolved.plan,
                isPersistedPlan: resolved.isPersisted,
                isReusedBlock: resolved.isReusedBlock,
                goalFocus: appSettings.goalFocusValue,
                rotationStyle: appSettings.rotationStyleValue,
                preferredSessionLengthMinutes: appSettings.preferredSessionLengthMinutes,
                completedTemplateSessions: completedTemplateSessions
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func shuffleTodayPlan() async -> String? {
        guard let todayPlan else {
            return "There is no generated plan to shuffle for today."
        }

        do {
            let baseExercises = try db.fetchTemplateExercises(templateId: todayPlan.template.id)
            let allExercises = try db.fetchAllExercises()
            let previous = planSnapshots(from: todayPlan)
            let nextShuffleCount = todayPlan.plan.shuffleCount + 1
            let build = try planGenerator.buildPlan(
                template: todayPlan.template,
                baseExercises: baseExercises,
                allExercises: allExercises,
                previousPlan: previous,
                shuffleSeed: nextShuffleCount
            )

            self.todayPlan = try db.saveWorkoutDayPlan(
                date: today,
                template: todayPlan.template,
                exercises: build.exercises,
                shuffleCount: nextShuffleCount,
                existingPlanId: todayPlan.plan.id
            )

            try await refreshShuffleAvailability()
            return nil
        } catch {
            let message = error.localizedDescription
            todayShuffleUnavailableReason = message
            return message
        }
    }

    private func reloadDisplayedMonth() async {
        do {
            try await loadMonthSummaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSettingsAndSchedule() async throws {
        let settings = try db.fetchSettings()
        let scheduleDays = try db.fetchScheduleWithTemplates()

        appSettings = settings
        weekStartsOn = settings.weekStartsOn
        self.scheduleDays = scheduleDays
        let todayWeekday = Calendar.current.component(.weekday, from: referenceToday) - 1
        todaySchedule = scheduleDays.first { $0.dayOfWeek == todayWeekday }
    }

    private func loadMonthSummaries() async throws {
        let summaries = try db.fetchWorkoutMonthSummaries(month: displayedMonth)
        monthSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date, $0) })
    }

    private func loadTodayCompletedSessions() async throws {
        todayCompletedSessions = try db.fetchCompletedSessions(on: today)
    }

    private func loadRecentCompletedSessions() async throws {
        recentCompletedSessions = try db.fetchRecentSessions(limit: 90)
    }

    private func loadTodayPlan() async throws {
        guard let todaySchedule, todaySchedule.template != nil, todaySchedule.isRestDay == false else {
            todayPlan = nil
            todayShuffleUnavailableReason = nil
            return
        }

        todayPlan = try resolveDayPlan(for: today, schedule: todaySchedule, persistIfNeeded: true).plan

        try await refreshShuffleAvailability()
    }

    private func refreshShuffleAvailability() async throws {
        guard let todayPlan else {
            todayShuffleUnavailableReason = nil
            return
        }

        do {
            let baseExercises = try db.fetchTemplateExercises(templateId: todayPlan.template.id)
            let allExercises = try db.fetchAllExercises()
            _ = try planGenerator.buildPlan(
                template: todayPlan.template,
                baseExercises: baseExercises,
                allExercises: allExercises,
                previousPlan: planSnapshots(from: todayPlan),
                shuffleSeed: todayPlan.plan.shuffleCount + 1
            )
            todayShuffleUnavailableReason = nil
        } catch {
            todayShuffleUnavailableReason = error.localizedDescription
        }
    }

    private func resolveDayPlan(
        for date: Date,
        schedule: ScheduleDay,
        persistIfNeeded: Bool
    ) throws -> ResolvedWorkoutDayPlan {
        guard let template = schedule.template, schedule.isRestDay == false else {
            throw NSError(
                domain: "TodayViewModel",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No workout template is scheduled for this day."]
            )
        }

        let normalizedDate = Calendar.current.startOfDay(for: date)
        let existingPlan = try db.fetchWorkoutDayPlan(date: normalizedDate, templateId: template.id)
        let replacementPlanID = existingPlan?.plan.id
        if let existing = existingPlan {
            let exercises = existing.exercises.map(\.exercise)
            if planGenerator.supportsSavedPlan(template: template, exercises: exercises) {
                return ResolvedWorkoutDayPlan(plan: existing, isPersisted: true, isReusedBlock: false)
            }
        }

        let rotationStyle = appSettings.rotationStyleValue
        let completedTemplateSessions = try db.fetchCompletedSessionCount(templateId: template.id, before: normalizedDate)

        if rotationStyle.cadenceSessions > 1,
           completedTemplateSessions > 0,
           completedTemplateSessions % rotationStyle.cadenceSessions != 0,
           let latestPlan = try db.fetchLatestWorkoutDayPlan(templateId: template.id, before: normalizedDate),
           planGenerator.supportsSavedPlan(template: template, exercises: latestPlan.exercises.map(\.exercise)) {
            let reusedPlan = try materializeDayPlan(
                date: normalizedDate,
                template: template,
                drafts: planDrafts(from: latestPlan),
                persistIfNeeded: persistIfNeeded,
                shuffleCount: 0,
                existingPlanId: replacementPlanID
            )
            return ResolvedWorkoutDayPlan(plan: reusedPlan, isPersisted: persistIfNeeded, isReusedBlock: true)
        }

        let baseExercises = try db.fetchTemplateExercises(templateId: template.id)
        let allExercises = try db.fetchAllExercises()
        let previousPlan = try db.fetchLatestPlanSnapshot(templateId: template.id, before: normalizedDate)
            ?? db.fetchLatestCompletedSessionSnapshot(templateId: template.id, before: normalizedDate)
        let build = try planGenerator.buildPlan(
            template: template,
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: previousPlan,
            shuffleSeed: rotationSeed(
                completedSessionCount: completedTemplateSessions,
                style: rotationStyle
            )
        )

        let plan = try materializeDayPlan(
            date: normalizedDate,
            template: template,
            drafts: build.exercises,
            persistIfNeeded: persistIfNeeded,
            shuffleCount: 0,
            existingPlanId: replacementPlanID
        )

        return ResolvedWorkoutDayPlan(plan: plan, isPersisted: persistIfNeeded, isReusedBlock: false)
    }

    private func materializeDayPlan(
        date: Date,
        template: WorkoutTemplate,
        drafts: [WorkoutPlanExerciseDraft],
        persistIfNeeded: Bool,
        shuffleCount: Int,
        existingPlanId: UUID? = nil
    ) throws -> WorkoutDayPlanWithExercises {
        if persistIfNeeded {
            return try db.saveWorkoutDayPlan(
                date: date,
                template: template,
                exercises: drafts,
                shuffleCount: shuffleCount,
                existingPlanId: existingPlanId
            )
        }

        let plan = WorkoutDayPlan(
            date: Calendar.current.startOfDay(for: date),
            templateId: template.id,
            shuffleCount: shuffleCount
        )

        let exercises = drafts
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { draft in
                WorkoutDayPlanExerciseDetail(
                    planExercise: WorkoutDayPlanExercise(
                        planId: plan.id,
                        exerciseId: draft.exercise.id,
                        sortOrder: draft.sortOrder,
                        targetSets: draft.targetSets,
                        targetReps: draft.targetReps,
                        targetDuration: draft.targetDuration,
                        targetWeight: draft.targetWeight,
                        isAnchor: draft.isAnchor
                    ),
                    exercise: draft.exercise
                )
            }

        return WorkoutDayPlanWithExercises(plan: plan, template: template, exercises: exercises)
    }

    private func planDrafts(from dayPlan: WorkoutDayPlanWithExercises) -> [WorkoutPlanExerciseDraft] {
        dayPlan.exercises.map { detail in
            WorkoutPlanExerciseDraft(
                exercise: detail.exercise,
                sortOrder: detail.planExercise.sortOrder,
                targetSets: detail.planExercise.targetSets,
                targetReps: detail.planExercise.targetReps,
                targetDuration: detail.planExercise.targetDuration,
                targetWeight: detail.planExercise.targetWeight,
                isAnchor: detail.planExercise.isAnchor
            )
        }
    }

    private func rotationSeed(
        completedSessionCount: Int,
        style: WorkoutRotationStyle
    ) -> Int {
        completedSessionCount / max(1, style.cadenceSessions)
    }

    private func buildMonthGrid(for month: Date) -> [CalendarMonthDay] {
        let calendar = Calendar.current
        let monthStart = Self.startOfMonth(for: month)
        let monthRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let firstWeekday = calendar.component(.weekday, from: monthStart) - 1
        let leadingDays = (firstWeekday - weekStartsOn + 7) % 7
        var days: [CalendarMonthDay] = []

        if leadingDays > 0 {
            for offset in stride(from: leadingDays, to: 0, by: -1) {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { continue }
                days.append(calendarDay(for: date, isInDisplayedMonth: false))
            }
        }

        for day in monthRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            days.append(calendarDay(for: date, isInDisplayedMonth: true))
        }

        let trailingDays = (7 - (days.count % 7)) % 7
        if trailingDays > 0,
           let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) {
            for offset in 1...trailingDays {
                guard let date = calendar.date(byAdding: .day, value: offset, to: monthEnd) else { continue }
                days.append(calendarDay(for: date, isInDisplayedMonth: false))
            }
        }

        return days
    }

    private func calendarDay(for date: Date, isInDisplayedMonth: Bool) -> CalendarMonthDay {
        let normalized = Calendar.current.startOfDay(for: date)
        let scheduledDay = scheduleDay(for: normalized)
        let isScheduledWorkout = scheduledDay?.isRestDay == false && scheduledDay?.template != nil
        let isRestDay = scheduledDay?.isRestDay == true
        let hasCompletedWorkout = monthSummaries[normalized] != nil

        return CalendarMonthDay(
            date: normalized,
            isInDisplayedMonth: isInDisplayedMonth,
            isToday: Calendar.current.isDate(normalized, inSameDayAs: referenceToday),
            summary: monthSummaries[normalized],
            isScheduledWorkout: isScheduledWorkout,
            isRestDay: isRestDay,
            isMissedWorkout: isScheduledWorkout && normalized < today && !hasCompletedWorkout
        )
    }

    private func scheduleDay(for date: Date) -> ScheduleDay? {
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return scheduleDays.first { $0.dayOfWeek == weekday }
    }

    private func planSnapshots(from dayPlan: WorkoutDayPlanWithExercises) -> [WorkoutPlanExerciseSnapshot] {
        dayPlan.exercises.map {
            WorkoutPlanExerciseSnapshot(
                exercise: $0.exercise,
                sortOrder: $0.planExercise.sortOrder,
                isAnchor: $0.planExercise.isAnchor
            )
        }
    }

    private func expectedWorkoutCount(in month: Date, upTo limitDate: Date?) -> Int {
        guard !scheduleDays.isEmpty else { return 0 }

        let calendar = Calendar.current
        let monthStart = Self.startOfMonth(for: month)
        let monthEndBase = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        let monthEnd = limitDate.map { min(calendar.startOfDay(for: $0), monthEndBase) } ?? monthEndBase

        guard monthEnd >= monthStart else { return 0 }

        var count = 0
        var cursor = monthStart

        while cursor <= monthEnd {
            let weekday = calendar.component(.weekday, from: cursor) - 1
            if let scheduledDay = scheduleDays.first(where: { $0.dayOfWeek == weekday }),
               scheduledDay.isRestDay == false,
               scheduledDay.template != nil {
                count += 1
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }

        return count
    }

    private func workoutExpectationBreakdown(in month: Date) -> (expected: Int, missed: Int, remaining: Int) {
        guard !scheduleDays.isEmpty else { return (0, 0, 0) }

        let calendar = Calendar.current
        let monthStart = Self.startOfMonth(for: month)
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        var expected = 0
        var missed = 0
        var remaining = 0
        var cursor = monthStart

        while cursor <= monthEnd {
            let normalized = calendar.startOfDay(for: cursor)
            let scheduledDay = scheduleDay(for: normalized)
            let isScheduledWorkout = scheduledDay?.isRestDay == false && scheduledDay?.template != nil
            let hasCompletedWorkout = monthSummaries[normalized] != nil

            if isScheduledWorkout {
                expected += 1

                if normalized < today && !hasCompletedWorkout {
                    missed += 1
                } else if normalized >= today && !hasCompletedWorkout {
                    remaining += 1
                }
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: normalized) else { break }
            cursor = nextDay
        }

        return (expected, missed, remaining)
    }

    private static func startOfMonth(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }
}
