import Foundation
import SwiftUI
import UserNotifications

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var exportMessage: String?

    private let db = DatabaseService.shared

    init() {
        Task {
            await loadSettings()
        }
    }

    func loadSettings() async {
        isLoading = true
        do {
            settings = try db.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveSettings() async -> Bool {
        do {
            try db.saveSettings(settings)

            // Update notifications if needed
            if settings.workoutReminderEnabled {
                await scheduleWorkoutReminders()
            } else {
                cancelWorkoutReminders()
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateDefaultRestTime(_ time: Int) async {
        settings.defaultRestTime = time
        await saveSettings()
    }

    func updateWorkoutReminder(enabled: Bool) async {
        settings.workoutReminderEnabled = enabled
        await saveSettings()
    }

    func updateReminderTime(_ time: Date) async {
        settings.workoutReminderTime = time
        await saveSettings()
    }

    func updateRestTimerSound(_ enabled: Bool) async {
        settings.restTimerSound = enabled
        await saveSettings()
    }

    func updateRestTimerHaptic(_ enabled: Bool) async {
        settings.restTimerHaptic = enabled
        await saveSettings()
    }

    func updateWeekStartsOn(_ day: Int) async {
        settings.weekStartsOn = day
        await saveSettings()
    }

    // MARK: - Notifications

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func scheduleWorkoutReminders() async {
        let center = UNUserNotificationCenter.current()

        // Cancel existing reminders
        center.removePendingNotificationRequests(withIdentifiers: (0..<7).map { "workout_reminder_\($0)" })

        // Get schedule
        do {
            let schedule = try db.fetchScheduleWithTemplates()

            for day in schedule where !day.isRestDay {
                if let template = day.template {
                    let content = UNMutableNotificationContent()
                    content.title = "Time for \(template.name)!"
                    content.body = "Your scheduled workout is waiting."
                    content.sound = .default

                    var dateComponents = Calendar.current.dateComponents([.hour, .minute], from: settings.workoutReminderTime)
                    dateComponents.weekday = day.dayOfWeek + 1 // UNCalendarNotificationTrigger uses 1-indexed weekdays

                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "workout_reminder_\(day.dayOfWeek)",
                        content: content,
                        trigger: trigger
                    )

                    try await center.add(request)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelWorkoutReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<7).map { "workout_reminder_\($0)" })
    }

    // MARK: - Export

    func exportJSON() -> URL? {
        do {
            let data = try db.exportToJSON()
            let fileName = "workout_export_\(Date().ISO8601Format()).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url)
            exportMessage = "Export successful"
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportCSV() -> [URL] {
        do {
            let csvFiles = try db.exportToCSV()
            var urls: [URL] = []

            for (filename, content) in csvFiles {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try content.write(to: url, atomically: true, encoding: .utf8)
                urls.append(url)
            }

            exportMessage = "Export successful"
            return urls
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
