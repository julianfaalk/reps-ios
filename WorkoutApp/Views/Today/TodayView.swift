import SwiftUI

struct TodayView: View {
    @StateObject private var scheduleViewModel = ScheduleViewModel()
    @StateObject private var historyViewModel = HistoryViewModel()
    @EnvironmentObject var workoutViewModel: WorkoutViewModel

    @State private var showingTemplateList = false
    @State private var showingWorkout = false
    @State private var showingWorkoutOverview = false
    @State private var selectedRecentSession: SessionWithDetails?

    var todaySchedule: ScheduleDay? {
        scheduleViewModel.getTodaySchedule()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Today's Workout Card
                    TodayWorkoutCard(
                        schedule: todaySchedule,
                        onStartWorkout: { template in
                            Task {
                                await workoutViewModel.startSession(templateId: template?.id)
                                showingWorkout = true
                            }
                        },
                        onSelectTemplate: {
                            showingTemplateList = true
                        }
                    )

                    // Quick Actions
                    QuickActionsSection(
                        onStartEmpty: {
                            Task {
                                await workoutViewModel.startAdHocSession()
                                showingWorkout = true
                            }
                        },
                        onSelectTemplate: {
                            showingTemplateList = true
                        }
                    )

                    // Recent Workouts
                    RecentWorkoutsSection(
                        sessions: historyViewModel.sessions.prefix(3).map { $0 },
                        onOpenSession: { session in
                            selectedRecentSession = session
                        },
                        onOpenAll: {
                            showingWorkoutOverview = true
                        }
                    )
                }
                .padding()
            }
            .navigationTitle("Today")
            .refreshable {
                await scheduleViewModel.loadSchedule()
                await historyViewModel.loadSessions()
            }
            .sheet(isPresented: $showingTemplateList) {
                TemplatePickerView { template in
                    Task {
                        await workoutViewModel.startSession(templateId: template.id)
                        showingWorkout = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingWorkout) {
                LiveWorkoutView()
                    .environmentObject(workoutViewModel)
            }
            .sheet(item: $selectedRecentSession, onDismiss: {
                Task {
                    await historyViewModel.loadSessions()
                }
            }) { session in
                HistoryDetailView(sessionId: session.session.id, viewModel: historyViewModel)
            }
            .sheet(isPresented: $showingWorkoutOverview, onDismiss: {
                Task {
                    await historyViewModel.loadSessions()
                }
            }) {
                HistoryView()
            }
        }
    }
}

struct TodayWorkoutCard: View {
    let schedule: ScheduleDay?
    let onStartWorkout: (WorkoutTemplate?) -> Void
    let onSelectTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date(), style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let schedule = schedule {
                        if schedule.isRestDay {
                            Text("Rest Day")
                                .font(.title2)
                                .fontWeight(.bold)
                        } else if let template = schedule.template {
                            Text(template.name)
                                .font(.title2)
                                .fontWeight(.bold)
                        } else {
                            Text("No Workout Scheduled")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    } else {
                        Text("No Schedule Set")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                Spacer()

                Image(systemName: schedule?.isRestDay == true ? "moon.zzz.fill" : "figure.strengthtraining.traditional")
                    .font(.system(size: 40))
                    .foregroundColor(schedule?.isRestDay == true ? .orange : .accentColor)
            }

            if schedule?.isRestDay != true {
                Button {
                    onStartWorkout(schedule?.template)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Workout")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
    }
}

struct QuickActionsSection: View {
    let onStartEmpty: () -> Void
    let onSelectTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Empty Session",
                    icon: "plus.circle",
                    color: .green
                ) {
                    onStartEmpty()
                }

                QuickActionButton(
                    title: "From Template",
                    icon: "doc.text",
                    color: .blue
                ) {
                    onSelectTemplate()
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(12)
        }
    }
}

struct RecentWorkoutsSection: View {
    let sessions: [SessionWithDetails]
    let onOpenSession: (SessionWithDetails) -> Void
    let onOpenAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Workouts")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Button("View All") {
                    onOpenAll()
                }
                .font(.subheadline)
            }

            if sessions.isEmpty {
                Text("No recent workouts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(sessions) { session in
                    Button {
                        onOpenSession(session)
                    } label: {
                        RecentWorkoutRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RecentWorkoutRow: View {
    let session: SessionWithDetails

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.template?.name ?? "Ad-hoc Workout")
                    .font(.headline)

                Text(session.session.startedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(session.session.formattedDuration)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.caption2)
                    Text("\(session.totalSets) sets")
                }
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct TemplatePickerView: View {
    @StateObject private var viewModel = TemplateViewModel()
    @Environment(\.dismiss) private var dismiss

    let onSelect: (WorkoutTemplate) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "doc.text",
                        description: Text("Create a template in the Schedule tab first")
                    )
                } else {
                    List(viewModel.templates) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            TemplateRowView(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    TodayView()
        .environmentObject(WorkoutViewModel())
}
