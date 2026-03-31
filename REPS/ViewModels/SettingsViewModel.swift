import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var exportMessage: String?

    private let db = DatabaseService.shared
    private let notificationService = NotificationService.shared
    private let localization = LocalizationService.shared

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

    func updatePreferredLanguage(_ language: AppLanguage) async {
        settings.preferredLanguageValue = language
        await saveSettings()
    }

    func updateMotivationPush(enabled: Bool) async {
        settings.motivationPushEnabled = enabled
        await saveSettings()
    }

    func updateSocialPush(enabled: Bool) async {
        settings.socialPushEnabled = enabled
        await saveSettings()
    }

    func updateQuietHours(start: String, end: String) async {
        settings.quietHoursStart = start
        settings.quietHoursEnd = end
        await saveSettings()
    }

    // MARK: - Notifications

    func requestNotificationPermission() async -> Bool {
        await notificationService.requestPermission()
    }

    private func scheduleWorkoutReminders() async {
        // Get schedule
        do {
            let schedule = try db.fetchScheduleWithTemplates()
            await notificationService.scheduleWorkoutReminders(
                for: schedule,
                at: settings.workoutReminderTime,
                goalFocus: settings.goalFocusValue
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelWorkoutReminders() {
        notificationService.cancelWorkoutReminders()
    }

    // MARK: - Database

    func resetDatabase() async {
        isLoading = true
        do {
            try db.resetAndReseedDatabase()
            exportMessage = localization.localized("profile.reset.success")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Export

    func exportJSON() -> URL? {
        do {
            let data = try db.exportToJSON()
            let fileName = "reps_backup_\(Date().ISO8601Format()).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url)
            exportMessage = localization.localized("profile.export.success")
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

            exportMessage = localization.localized("profile.export.success")
            return urls
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func importBackup(from url: URL) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let summary = try db.importFromJSON(data)
            exportMessage = importSuccessMessage(for: summary)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func importSuccessMessage(for summary: DatabaseService.ImportSummary) -> String {
        switch localization.selectedLanguage {
        case .german:
            return "Import abgeschlossen: \(summary.workoutSessions) Workouts, \(summary.measurements) Messungen und \(summary.exercises) Übungen."
        default:
            return "Import finished: \(summary.workoutSessions) workouts, \(summary.measurements) measurements, and \(summary.exercises) exercises."
        }
    }
}
