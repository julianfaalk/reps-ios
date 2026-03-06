import Foundation
import SwiftUI

struct CalendarMonthDay: Identifiable, Hashable {
    var date: Date
    var isInDisplayedMonth: Bool
    var isToday: Bool
    var summary: WorkoutCalendarDaySummary?

    var id: Date { date }
}

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var todaySchedule: ScheduleDay?
    @Published var displayedMonth: Date
    @Published var weekStartsOn: Int = 1
    @Published var monthSummaries: [Date: WorkoutCalendarDaySummary] = [:]
    @Published var todayPlan: WorkoutDayPlanWithExercises?
    @Published var todayShuffleUnavailableReason: String?
    @Published var selectedDaySessions: [SessionWithDetails] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db: DatabaseService
    private let planGenerator = WorkoutPlanGenerator()
    private let referenceToday: Date

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

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            try await loadSettingsAndSchedule()
            try await loadMonthSummaries()
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

        weekStartsOn = settings.weekStartsOn
        let todayWeekday = Calendar.current.component(.weekday, from: referenceToday) - 1
        todaySchedule = scheduleDays.first { $0.dayOfWeek == todayWeekday }
    }

    private func loadMonthSummaries() async throws {
        let summaries = try db.fetchWorkoutMonthSummaries(month: displayedMonth)
        monthSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date, $0) })
    }

    private func loadTodayPlan() async throws {
        guard let template = todaySchedule?.template, todaySchedule?.isRestDay == false else {
            todayPlan = nil
            todayShuffleUnavailableReason = nil
            return
        }

        if let existing = try db.fetchWorkoutDayPlan(date: today, templateId: template.id) {
            todayPlan = existing
        } else {
            let baseExercises = try db.fetchTemplateExercises(templateId: template.id)
            let allExercises = try db.fetchAllExercises()
            let previousPlan = try db.fetchLatestPlanSnapshot(templateId: template.id, before: today)
                ?? db.fetchLatestCompletedSessionSnapshot(templateId: template.id, before: today)
            let build = try planGenerator.buildPlan(
                template: template,
                baseExercises: baseExercises,
                allExercises: allExercises,
                previousPlan: previousPlan,
                shuffleSeed: 0
            )

            todayPlan = try db.saveWorkoutDayPlan(
                date: today,
                template: template,
                exercises: build.exercises,
                shuffleCount: 0
            )
        }

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
        return CalendarMonthDay(
            date: normalized,
            isInDisplayedMonth: isInDisplayedMonth,
            isToday: Calendar.current.isDate(normalized, inSameDayAs: referenceToday),
            summary: monthSummaries[normalized]
        )
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

    private static func startOfMonth(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }
}
