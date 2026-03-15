import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var sessionViewModel: AppSessionViewModel
    @EnvironmentObject private var storeManager: StoreManager
    @State private var showingExportOptions = false
    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []
    @State private var showingResetAlert = false
    @State private var showingSuccessAlert = false
    @State private var showingPaywall = false
    @State private var showingDeleteAccountAlert = false

    var body: some View {
        NavigationStack {
            Form {
                if let currentUser = sessionViewModel.currentUser {
                    Section("Cloud Account") {
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

                            Text(storeManager.isPremium ? "Premium" : "Free")
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
                            }
                        } label: {
                            Label(sessionViewModel.isSyncing ? "Sync laeuft ..." : "Jetzt mit Workout Cloud synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sessionViewModel.isSyncing)
                    }
                }

                Section("Premium") {
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack {
                            Label("Workout App Premium", systemImage: storeManager.isPremium ? "crown.fill" : "sparkles")
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
                        Label("Kaeufe wiederherstellen", systemImage: "arrow.clockwise.circle.fill")
                    }
                }

                Section("Timers") {
                    HStack {
                        Text("Default Rest Time")
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

                Section("Notifications") {
                    Toggle("Workout Reminders", isOn: Binding(
                        get: { viewModel.settings.workoutReminderEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    let granted = await viewModel.requestNotificationPermission()
                                    if granted {
                                        await viewModel.updateWorkoutReminder(enabled: true)
                                    }
                                } else {
                                    await viewModel.updateWorkoutReminder(enabled: false)
                                }
                            }
                        }
                    ))

                    if viewModel.settings.workoutReminderEnabled {
                        DatePicker(
                            "Reminder Time",
                            selection: Binding(
                                get: { viewModel.settings.workoutReminderTime },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateReminderTime(newValue)
                                    }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle("Rest Timer Sound", isOn: Binding(
                        get: { viewModel.settings.restTimerSound },
                        set: { newValue in
                            Task {
                                await viewModel.updateRestTimerSound(newValue)
                            }
                        }
                    ))

                    Toggle("Rest Timer Haptic", isOn: Binding(
                        get: { viewModel.settings.restTimerHaptic },
                        set: { newValue in
                            Task {
                                await viewModel.updateRestTimerHaptic(newValue)
                            }
                        }
                    ))
                }

                Section("Calendar") {
                    Picker("Week Starts On", selection: Binding(
                        get: { viewModel.settings.weekStartsOn },
                        set: { newValue in
                            Task {
                                await viewModel.updateWeekStartsOn(newValue)
                            }
                        }
                    )) {
                        Text("Sunday").tag(0)
                        Text("Monday").tag(1)
                    }
                }

                Section("Data") {
                    Button {
                        if storeManager.isPremium {
                            showingExportOptions = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset Database", systemImage: "trash")
                    }
                }

                Section("About") {
                    Link(destination: AppConfig.privacyURL) {
                        Label("Privacy Policy", systemImage: "lock.shield.fill")
                    }

                    Link(destination: AppConfig.termsURL) {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Account") {
                    Button {
                        sessionViewModel.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showingDeleteAccountAlert = true
                    } label: {
                        Label("Delete Cloud Account", systemImage: "trash.fill")
                    }
                }

                Section {
                    Text("Workouts bleiben lokal auf deinem Geraet. Workout Cloud speichert dein Konto, Premium-Status und die wichtigsten Fortschrittskennzahlen dauerhaft.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Export Format", isPresented: $showingExportOptions) {
                Button("JSON") {
                    if let url = viewModel.exportJSON() {
                        exportURLs = [url]
                        showingShareSheet = true
                        showingSuccessAlert = true
                    } else {
                        // Error is already shown via errorMessage alert
                    }
                }

                Button("CSV") {
                    let urls = viewModel.exportCSV()
                    if !urls.isEmpty {
                        exportURLs = urls
                        showingShareSheet = true
                        showingSuccessAlert = true
                    } else {
                        // Error is already shown via errorMessage alert
                    }
                }

                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: exportURLs)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(storeManager)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Reset Database?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    Task {
                        await viewModel.resetDatabase()
                        showingSuccessAlert = true
                    }
                }
            } message: {
                Text("This will delete all data and restore default templates and schedule. This cannot be undone.")
            }
            .alert("Success", isPresented: $showingSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.exportMessage ?? "Operation completed successfully")
            }
            .alert("Delete Cloud Account?", isPresented: $showingDeleteAccountAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await sessionViewModel.deleteAccount()
                    }
                }
            } message: {
                Text("This removes your Workout Cloud account and server-side profile data. Local workout data on this iPhone remains until you reset the database.")
            }
            .onDisappear {
                Task {
                    await sessionViewModel.syncSnapshot()
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
}
