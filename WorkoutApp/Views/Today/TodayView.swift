import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @EnvironmentObject var workoutViewModel: WorkoutViewModel

    @State private var showingTemplateList = false
    @State private var showingWorkout = false
    @State private var showingWorkoutOverview = false
    @State private var selectedHistoryDate: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TodayHeroCard(
                        schedule: viewModel.todaySchedule,
                        dayPlan: viewModel.todayPlan,
                        shuffleUnavailableReason: viewModel.todayShuffleUnavailableReason,
                        onStartWorkout: startTodayWorkout,
                        onShuffle: shuffleTodayPlan,
                        onSelectTemplate: { showingTemplateList = true }
                    )

                    TodayQuickActionsSection(
                        onStartEmpty: {
                            Task {
                                await workoutViewModel.startAdHocSession()
                                showingWorkout = workoutViewModel.isWorkoutActive
                            }
                        },
                        onSelectTemplate: { showingTemplateList = true },
                        onOpenHistory: { showingWorkoutOverview = true }
                    )

                    WorkoutCalendarSection(
                        monthTitle: viewModel.displayedMonthTitle,
                        weekdaySymbols: viewModel.weekdaySymbols,
                        days: viewModel.monthGridDays,
                        onPreviousMonth: {
                            Task { await viewModel.showPreviousMonth() }
                        },
                        onNextMonth: {
                            Task { await viewModel.showNextMonth() }
                        },
                        onOpenDay: { day in
                            Task {
                                await viewModel.loadHistory(for: day.date)
                                selectedHistoryDate = day.date
                            }
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(isPresented: $showingTemplateList) {
                TemplatePickerView { template in
                    Task {
                        await workoutViewModel.startSession(templateId: template.id)
                        showingWorkout = workoutViewModel.isWorkoutActive
                    }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedHistoryDate != nil },
                    set: { if !$0 { selectedHistoryDate = nil } }
                )
            ) {
                if let selectedHistoryDate {
                    DayWorkoutHistorySheet(date: selectedHistoryDate, sessions: viewModel.selectedDaySessions)
                }
            }
            .sheet(isPresented: $showingWorkoutOverview) {
                HistoryView()
            }
            .fullScreenCover(
                isPresented: $showingWorkout,
                onDismiss: {
                    Task {
                        await viewModel.refresh()
                    }
                }
            ) {
                LiveWorkoutView()
                    .environmentObject(workoutViewModel)
            }
        }
    }

    private func startTodayWorkout() {
        guard let dayPlan = viewModel.todayPlan else {
            showingTemplateList = true
            return
        }

        Task {
            await workoutViewModel.startSession(dayPlan: dayPlan)
            showingWorkout = workoutViewModel.isWorkoutActive
        }
    }

    private func shuffleTodayPlan() {
        Task {
            _ = await viewModel.shuffleTodayPlan()
        }
    }
}

private struct TodayHeroCard: View {
    let schedule: ScheduleDay?
    let dayPlan: WorkoutDayPlanWithExercises?
    let shuffleUnavailableReason: String?
    let onStartWorkout: () -> Void
    let onShuffle: () -> Void
    let onSelectTemplate: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.18, blue: 0.27),
                            Color(red: 0.16, green: 0.32, blue: 0.24),
                            Color(red: 0.23, green: 0.48, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))

                        Text(titleText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Image(systemName: iconName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(12)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Text(subtitleText)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.78))

                if let dayPlan, !dayPlan.exercises.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(dayPlan.exercises) { detail in
                                PlanExerciseChip(detail: detail)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                actionArea
            }
            .padding(22)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 10)
    }

    private var titleText: String {
        if schedule?.isRestDay == true {
            return "Recovery Day"
        }
        if let dayPlan {
            return dayPlan.template.name
        }
        if let template = schedule?.template {
            return template.name
        }
        return "No Workout Scheduled"
    }

    private var subtitleText: String {
        if schedule?.isRestDay == true {
            return "Keep the streak alive tomorrow. Mobility, steps, and recovery count."
        }
        if let dayPlan {
            let anchors = dayPlan.exercises.filter { $0.planExercise.isAnchor }.map(\.exercise.name)
            if anchors.isEmpty {
                return "\(dayPlan.exercises.count) exercises ready for today."
            }
            return "Anchors today: \(anchors.joined(separator: " • "))"
        }
        return "Pick a template or start an empty session when you want to train freestyle."
    }

    private var iconName: String {
        if schedule?.isRestDay == true {
            return "moon.zzz.fill"
        }
        return dayPlan == nil ? "calendar.badge.plus" : "figure.strengthtraining.traditional"
    }

    @ViewBuilder
    private var actionArea: some View {
        if schedule?.isRestDay == true {
            Button(action: onSelectTemplate) {
                Label("Train Anyway", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        } else if dayPlan == nil && schedule?.template == nil {
            Button(action: onSelectTemplate) {
                Label("Choose Template", systemImage: "rectangle.grid.2x2.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        } else {
            HStack(spacing: 12) {
                Button(action: onStartWorkout) {
                    Label("Start Workout", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(Color.black.opacity(0.82))
                }

                Button(action: onShuffle) {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(dayPlan == nil || shuffleUnavailableReason != nil)
                .opacity(dayPlan == nil || shuffleUnavailableReason != nil ? 0.45 : 1)
            }

            if let shuffleUnavailableReason, dayPlan != nil {
                Text(shuffleUnavailableReason)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

private struct PlanExerciseChip: View {
    let detail: WorkoutDayPlanExerciseDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if detail.planExercise.isAnchor {
                    Text("Anchor")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.22), in: Capsule())
                }
                Text(detail.exercise.name)
                    .lineLimit(2)
            }
            .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                if let sets = detail.planExercise.targetSets {
                    Label("\(sets)", systemImage: "square.stack.3d.up")
                }
                if let reps = detail.planExercise.targetReps {
                    Label("\(reps)", systemImage: "repeat")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TodayQuickActionsSection: View {
    let onStartEmpty: () -> Void
    let onSelectTemplate: () -> Void
    let onOpenHistory: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                QuickActionTile(title: "Empty Session", icon: "plus.circle.fill", tint: Color.green, action: onStartEmpty)
                QuickActionTile(title: "Choose Template", icon: "rectangle.grid.2x2.fill", tint: Color.blue, action: onSelectTemplate)
                QuickActionTile(title: "History", icon: "clock.arrow.circlepath", tint: Color.orange, action: onOpenHistory)
            }
        }
    }
}

private struct QuickActionTile: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutCalendarSection: View {
    let monthTitle: String
    let weekdaySymbols: [String]
    let days: [CalendarMonthDay]
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onOpenDay: (CalendarMonthDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout Calendar")
                        .font(.title3.weight(.bold))
                    Text("Tap any 🔥 day to open that workout history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    CalendarNavButton(icon: "chevron.left", action: onPreviousMonth)
                    Text(monthTitle)
                        .font(.headline)
                        .frame(minWidth: 128)
                    CalendarNavButton(icon: "chevron.right", action: onNextMonth)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { day in
                    CalendarDayCell(day: day) {
                        onOpenDay(day)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct CalendarNavButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(Color(.systemBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarDayCell: View {
    let day: CalendarMonthDay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.subheadline.weight(day.isToday ? .bold : .medium))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)

                if let summary = day.summary {
                    HStack(spacing: 4) {
                        Text("🔥")
                        if summary.workoutCount > 1 {
                            Text("\(summary.workoutCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(textColor)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(day.isToday ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(day.summary == nil)
    }

    private var backgroundColor: Color {
        if day.isToday {
            return Color.accentColor.opacity(0.12)
        }
        if day.summary != nil {
            return Color.orange.opacity(0.12)
        }
        return day.isInDisplayedMonth ? Color(.systemBackground) : Color(.systemGray6)
    }

    private var textColor: Color {
        day.isInDisplayedMonth ? .primary : .secondary
    }
}

private struct DayWorkoutHistorySheet: View {
    let date: Date
    let sessions: [SessionWithDetails]

    @StateObject private var historyViewModel = HistoryViewModel()
    @State private var selectedSession: SessionWithDetails?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("There are no completed workouts stored for this day.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(sessions) { session in
                                Button {
                                    selectedSession = session
                                } label: {
                                    DayWorkoutRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.day().month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                HistoryDetailView(sessionId: session.session.id, viewModel: historyViewModel)
            }
        }
    }
}

private struct DayWorkoutRow: View {
    let session: SessionWithDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.template?.name ?? "Ad-hoc Workout")
                        .font(.headline)
                    Text(session.session.startedAt, format: .dateTime.hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(session.session.formattedDuration)
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 14) {
                Label("\(session.exercisesCompleted)", systemImage: "figure.strengthtraining.traditional")
                Label("\(session.totalSets)", systemImage: "square.stack.3d.up")
                Label("\(session.totalReps)", systemImage: "repeat")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
