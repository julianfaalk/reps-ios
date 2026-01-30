import Foundation
import SwiftUI

@MainActor
class ScheduleViewModel: ObservableObject {
    @Published var scheduleDays: [ScheduleDay] = []
    @Published var templates: [WorkoutTemplate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var weekStartsOn: Int = 1

    private let db = DatabaseService.shared

    init() {
        Task {
            await loadSchedule()
            await loadTemplates()
            await loadSettings()
            await setupDefaultScheduleIfNeeded()
        }
    }

    func loadSchedule() async {
        isLoading = true
        do {
            scheduleDays = try db.fetchScheduleWithTemplates()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadTemplates() async {
        do {
            templates = try db.fetchAllTemplates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSettings() async {
        do {
            let settings = try db.fetchSettings()
            weekStartsOn = settings.weekStartsOn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignTemplate(dayOfWeek: Int, templateId: UUID?) async -> Bool {
        do {
            let schedule = Schedule(
                dayOfWeek: dayOfWeek,
                templateId: templateId,
                isRestDay: templateId == nil
            )
            try db.saveSchedule(schedule)
            await loadSchedule()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markAsRestDay(dayOfWeek: Int) async -> Bool {
        do {
            let schedule = Schedule(
                dayOfWeek: dayOfWeek,
                templateId: nil,
                isRestDay: true
            )
            try db.saveSchedule(schedule)
            await loadSchedule()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func getTodaySchedule() -> ScheduleDay? {
        let today = Calendar.current.component(.weekday, from: Date()) - 1 // Convert to 0-indexed
        return scheduleDays.first { $0.dayOfWeek == today }
    }

    func getOrderedDays() -> [ScheduleDay] {
        var ordered: [ScheduleDay] = []
        for i in 0..<7 {
            let dayIndex = (weekStartsOn + i) % 7
            if let day = scheduleDays.first(where: { $0.dayOfWeek == dayIndex }) {
                ordered.append(day)
            } else {
                ordered.append(ScheduleDay(schedule: nil, template: nil, dayOfWeek: dayIndex))
            }
        }
        return ordered
    }

    private func setupDefaultScheduleIfNeeded() async {
        // Check if schedule is empty (no schedule entries exist)
        guard scheduleDays.allSatisfy({ $0.schedule == nil }) else {
            return // Schedule already has entries
        }

        // Find templates by name
        let pushTemplate = templates.first { $0.name.contains("Push") }
        let pullTemplate = templates.first { $0.name.contains("Pull") }
        let legsTemplate = templates.first { $0.name.contains("Legs") }
        let shouldersTemplate = templates.first { $0.name.contains("Schultern") || $0.name.contains("Arms") }

        // Only setup if we have the templates
        guard pushTemplate != nil || pullTemplate != nil || legsTemplate != nil || shouldersTemplate != nil else {
            return
        }

        // Setup default weekly schedule
        // 0 = Sunday, 1 = Monday, 2 = Tuesday, 3 = Wednesday, 4 = Thursday, 5 = Friday, 6 = Saturday
        let scheduleSetup: [(day: Int, template: WorkoutTemplate?, isRest: Bool)] = [
            (0, nil, true),                    // Sonntag: Rest
            (1, pushTemplate, false),          // Montag: Push
            (2, pullTemplate, false),          // Dienstag: Pull
            (3, legsTemplate, false),          // Mittwoch: Legs
            (4, nil, true),                    // Donnerstag: Rest
            (5, shouldersTemplate, false),     // Freitag: Shoulders/Arms
            (6, nil, true)                     // Samstag: Rest
        ]

        for setup in scheduleSetup {
            let schedule = Schedule(
                dayOfWeek: setup.day,
                templateId: setup.template?.id,
                isRestDay: setup.isRest
            )
            do {
                try db.saveSchedule(schedule)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Reload schedule to reflect changes
        await loadSchedule()
    }
}
