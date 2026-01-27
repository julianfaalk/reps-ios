import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingExportOptions = false
    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []

    var body: some View {
        NavigationStack {
            Form {
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
                        showingExportOptions = true
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                }

                Section("About") {
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

                Section {
                    Text("All data is stored locally on your device.")
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
                    }
                }

                Button("CSV") {
                    let urls = viewModel.exportCSV()
                    if !urls.isEmpty {
                        exportURLs = urls
                        showingShareSheet = true
                    }
                }

                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: exportURLs)
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
}
