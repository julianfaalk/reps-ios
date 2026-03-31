import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var sessionViewModel: AppSessionViewModel
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var localization: LocalizationService
    @State private var showingExportOptions = false
    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []
    @State private var showingImportPicker = false
    @State private var showingResetAlert = false
    @State private var showingSuccessAlert = false
    @State private var showingPaywall = false
    @State private var showingDeleteAccountAlert = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var importBackupTitle: String {
        switch localization.selectedLanguage {
        case .german:
            return "Backup importieren"
        default:
            return "Import Backup"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let currentUser = sessionViewModel.currentUser {
                    Section(localization.localized("profile.account.section")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentUser.resolvedDisplayName.isEmpty ? "Workout Cloud" : currentUser.resolvedDisplayName)
                                    .font(.headline)
                                if let email = currentUser.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Text(storeManager.isPremium
                                 ? localization.localized("profile.status.premium")
                                 : localization.localized("profile.status.free"))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    (storeManager.isPremium ? Color.green.opacity(0.18) : Color(.systemGray5)),
                                    in: Capsule()
                                )
                        }

                        Button {
                            Task {
                                await sessionViewModel.syncSnapshot()
                                await sessionViewModel.syncCurrentDevice()
                            }
                        } label: {
                            Label(
                                sessionViewModel.isSyncing
                                    ? localization.localized("profile.account.syncing")
                                    : localization.localized("profile.account.sync"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(sessionViewModel.isSyncing)
                    }
                }

                Section(localization.localized("profile.section")) {
                    NavigationLink {
                        ExerciseListView()
                    } label: {
                        Label(localization.localized("profile.exercise_library"), systemImage: "dumbbell")
                    }

                    Picker(localization.localized("profile.language"), selection: Binding(
                        get: { viewModel.settings.preferredLanguageValue },
                        set: { newValue in
                            localization.choose(newValue)
                            Task {
                                await viewModel.updatePreferredLanguage(newValue)
                                await sessionViewModel.syncSnapshot()
                                await sessionViewModel.syncCurrentDevice()
                            }
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                }

                Section(localization.localized("profile.premium.section")) {
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack {
                            Label(localization.localized("profile.premium.title"), systemImage: storeManager.isPremium ? "crown.fill" : "sparkles")
                            Spacer()
                            if storeManager.isPremium {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button {
                        Task {
                            await storeManager.restorePurchases()
                        }
                    } label: {
                        Label(localization.localized("profile.premium.restore"), systemImage: "arrow.clockwise.circle.fill")
                    }
                }

                Section(localization.localized("profile.timers.section")) {
                    HStack {
                        Text(localization.localized("profile.timers.default_rest"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { viewModel.settings.defaultRestTime },
                            set: { newValue in
                                Task {
                                    await viewModel.updateDefaultRestTime(newValue)
                                }
                            }
                        )) {
                            Text("30s").tag(30)
                            Text("60s").tag(60)
                            Text("90s").tag(90)
                            Text("120s").tag(120)
                            Text("180s").tag(180)
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section(localization.localized("profile.notifications.section")) {
                    Toggle(localization.localized("profile.notifications.workout_reminders"), isOn: Binding(
                        get: { viewModel.settings.workoutReminderEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    let granted = await viewModel.requestNotificationPermission()
                                    if granted {
                                        await viewModel.updateWorkoutReminder(enabled: true)
                                        await sessionViewModel.syncCurrentDevice()
                                    }
                                } else {
                                    await viewModel.updateWorkoutReminder(enabled: false)
                                    await sessionViewModel.syncCurrentDevice()
                                }
                            }
                        }
                    ))

                    if viewModel.settings.workoutReminderEnabled {
                        DatePicker(
                            localization.localized("profile.notifications.reminder_time"),
                            selection: Binding(
                                get: { viewModel.settings.workoutReminderTime },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateReminderTime(newValue)
                                        await sessionViewModel.syncSnapshot()
                                    }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle(localization.localized("profile.notifications.rest_sound"), isOn: Binding(
                        get: { viewModel.settings.restTimerSound },
                        set: { newValue in
                            Task {
                                await viewModel.updateRestTimerSound(newValue)
                            }
                        }
                    ))

                    Toggle(localization.localized("profile.notifications.motivation"), isOn: Binding(
                        get: { viewModel.settings.motivationPushEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    _ = await viewModel.requestNotificationPermission()
                                }
                                await viewModel.updateMotivationPush(enabled: newValue)
                                await sessionViewModel.syncSnapshot()
                                await sessionViewModel.syncCurrentDevice()
                            }
                        }
                    ))

                    Toggle(localization.localized("profile.notifications.social"), isOn: Binding(
                        get: { viewModel.settings.socialPushEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    _ = await viewModel.requestNotificationPermission()
                                }
                                await viewModel.updateSocialPush(enabled: newValue)
                                await sessionViewModel.syncSnapshot()
                                await sessionViewModel.syncCurrentDevice()
                            }
                        }
                    ))

                    if viewModel.settings.motivationPushEnabled || viewModel.settings.socialPushEnabled {
                        Picker(localization.localized("profile.notifications.quiet_start"), selection: Binding(
                            get: { viewModel.settings.quietHoursStart },
                            set: { newValue in
                                Task {
                                    await viewModel.updateQuietHours(start: newValue, end: viewModel.settings.quietHoursEnd)
                                    await sessionViewModel.syncSnapshot()
                                    await sessionViewModel.syncCurrentDevice()
                                }
                            }
                        )) {
                            Text("21:00").tag("21:00")
                            Text("22:00").tag("22:00")
                            Text("23:00").tag("23:00")
                        }

                        Picker(localization.localized("profile.notifications.quiet_end"), selection: Binding(
                            get: { viewModel.settings.quietHoursEnd },
                            set: { newValue in
                                Task {
                                    await viewModel.updateQuietHours(start: viewModel.settings.quietHoursStart, end: newValue)
                                    await sessionViewModel.syncSnapshot()
                                    await sessionViewModel.syncCurrentDevice()
                                }
                            }
                        )) {
                            Text("06:00").tag("06:00")
                            Text("07:00").tag("07:00")
                            Text("08:00").tag("08:00")
                            Text("09:00").tag("09:00")
                        }
                    }

                    Toggle(localization.localized("profile.notifications.rest_haptic"), isOn: Binding(
                        get: { viewModel.settings.restTimerHaptic },
                        set: { newValue in
                            Task {
                                await viewModel.updateRestTimerHaptic(newValue)
                            }
                        }
                    ))
                }

                Section(localization.localized("profile.calendar.section")) {
                    Picker(localization.localized("profile.calendar.week_start"), selection: Binding(
                        get: { viewModel.settings.weekStartsOn },
                        set: { newValue in
                            Task {
                                await viewModel.updateWeekStartsOn(newValue)
                            }
                        }
                    )) {
                        Text(localization.localized("profile.calendar.sunday")).tag(0)
                        Text(localization.localized("profile.calendar.monday")).tag(1)
                    }
                }

                Section(localization.localized("profile.data.section")) {
                    Button {
                        showingImportPicker = true
                    } label: {
                        Label(importBackupTitle, systemImage: "square.and.arrow.down")
                    }

                    Button {
                        if storeManager.isPremium {
                            showingExportOptions = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        Label(localization.localized("profile.data.export"), systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label(localization.localized("profile.data.reset"), systemImage: "trash")
                    }
                }

                Section(localization.localized("profile.about.section")) {
                    Link(destination: AppConfig.privacyURL) {
                        Label(localization.localized("profile.about.privacy"), systemImage: "lock.shield.fill")
                    }

                    Link(destination: AppConfig.termsURL) {
                        Label(localization.localized("profile.about.terms"), systemImage: "doc.text.fill")
                    }

                    HStack {
                        Text(localization.localized("profile.about.version"))
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(localization.localized("profile.about.build"))
                        Spacer()
                        Text(appBuild)
                            .foregroundColor(.secondary)
                    }
                }

                Section(localization.localized("profile.account.management")) {
                    Button {
                        sessionViewModel.signOut()
                    } label: {
                        Label(localization.localized("profile.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showingDeleteAccountAlert = true
                    } label: {
                        Label(localization.localized("profile.account.delete"), systemImage: "trash.fill")
                    }
                }

                Section {
                    Text(localization.localized("profile.storage.copy"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(localization.localized("tab.profile"))
            .confirmationDialog(localization.localized("profile.export.format"), isPresented: $showingExportOptions) {
                Button(localization.localized("profile.export.json")) {
                    if let url = viewModel.exportJSON() {
                        exportURLs = [url]
                        showingShareSheet = true
                        showingSuccessAlert = true
                    } else {
                        // Error is already shown via errorMessage alert
                    }
                }

                Button(localization.localized("profile.export.csv")) {
                    let urls = viewModel.exportCSV()
                    if !urls.isEmpty {
                        exportURLs = urls
                        showingShareSheet = true
                        showingSuccessAlert = true
                    } else {
                        // Error is already shown via errorMessage alert
                    }
                }

                Button(localization.localized("common.cancel"), role: .cancel) { }
            }
            .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task {
                        if await viewModel.importBackup(from: url) {
                            showingSuccessAlert = true
                        }
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: exportURLs)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(storeManager)
            }
            .alert(localization.localized("common.error"), isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(localization.localized("common.ok")) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(localization.localized("profile.reset.title"), isPresented: $showingResetAlert) {
                Button(localization.localized("common.cancel"), role: .cancel) { }
                Button(localization.localized("profile.reset.confirm"), role: .destructive) {
                    Task {
                        await viewModel.resetDatabase()
                        showingSuccessAlert = true
                    }
                }
            } message: {
                Text(localization.localized("profile.reset.message"))
            }
            .alert(localization.localized("common.success"), isPresented: $showingSuccessAlert) {
                Button(localization.localized("common.ok")) { }
            } message: {
                Text(viewModel.exportMessage ?? localization.localized("profile.success.operation"))
            }
            .alert(localization.localized("profile.delete.title"), isPresented: $showingDeleteAccountAlert) {
                Button(localization.localized("common.cancel"), role: .cancel) { }
                Button(localization.localized("profile.delete.confirm"), role: .destructive) {
                    Task {
                        await sessionViewModel.deleteAccount()
                    }
                }
            } message: {
                Text(localization.localized("profile.delete.message"))
            }
            .onDisappear {
                Task {
                    await sessionViewModel.syncSnapshot()
                    await sessionViewModel.syncCurrentDevice()
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

#Preview {
    SettingsView()
        .environmentObject(AppSessionViewModel())
        .environmentObject(StoreManager.shared)
        .environmentObject(LocalizationService.shared)
}
