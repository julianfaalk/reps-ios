import SwiftUI

private enum TodaySpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

private enum TodayPalette {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let navBar = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)
    static let subduedSurface = Color(uiColor: .tertiarySystemBackground)

    static var border: Color {
        Color.primary.opacity(0.08)
    }
}

private enum TodayHeroMode: Equatable {
    case active
    case completed
    case rest
    case planned
    case empty
}

private struct TodayInsightMetric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let tint: Color
}

private struct TodayInsightPayload: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let headline: String
    let message: String
    let tint: Color
    let metrics: [TodayInsightMetric]
}

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @EnvironmentObject var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var sessionViewModel: AppSessionViewModel
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var localization: LocalizationService

    @State private var showingTemplateList = false
    @State private var showingWorkout = false
    @State private var showingWorkoutOverview = false
    @State private var selectedHistoryDate: Date?
    @State private var selectedPlannedPreview: PlannedWorkoutPreview?
    @State private var shuffleMessage: String?
    @State private var selectedInsight: TodayInsightPayload?
    @State private var showingLockedPlanPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                TodayScreenBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: TodaySpacing.lg) {
                        if let lockedPlanSummary, !hasPremiumAccess {
                            TodayLockedPlanCard(
                                summary: lockedPlanSummary,
                                onUnlock: { showingLockedPlanPaywall = true }
                            )
                        }

                        TodayHeroCard(
                            schedule: viewModel.todaySchedule,
                            dayPlan: viewModel.todayPlan,
                            completedSessions: viewModel.todayCompletedSessions,
                            momentum: viewModel.todayMomentumSnapshot,
                            shuffleUnavailableReason: viewModel.todayShuffleUnavailableReason,
                            shuffleMessage: shuffleMessage,
                            hasActiveWorkout: workoutViewModel.isWorkoutActive,
                            activeExerciseName: workoutViewModel.currentExercise?.exercise.name,
                            onPrimaryAction: startTodayWorkout,
                            onShuffle: shuffleTodayPlan,
                            onSelectTemplate: { showingTemplateList = true },
                            onOpenCompletedHistory: openTodayHistory,
                            onOpenStatusInsight: { selectedInsight = statusInsight }
                        )

                        if shouldSurfaceMomentumBeforeQuickActions {
                            TodayMomentumSection(
                                snapshot: viewModel.todayMomentumSnapshot,
                                onOpenScoreInsight: { selectedInsight = momentumInsight },
                                onOpenStreakInsight: { selectedInsight = streakInsight },
                                onOpenConsistencyInsight: { selectedInsight = consistencyInsight },
                                onOpenWeeklyInsight: { selectedInsight = weeklyInsight }
                            )

                            TodayQuickActionsSection(
                                isWorkoutActive: workoutViewModel.isWorkoutActive,
                                onResumeWorkout: { showingWorkout = workoutViewModel.isWorkoutActive },
                                onStartEmpty: {
                                    Task {
                                        await workoutViewModel.startAdHocSession()
                                        showingWorkout = workoutViewModel.isWorkoutActive
                                    }
                                },
                                onSelectTemplate: { showingTemplateList = true },
                                onOpenHistory: { showingWorkoutOverview = true }
                            )
                        } else {
                            TodayQuickActionsSection(
                                isWorkoutActive: workoutViewModel.isWorkoutActive,
                                onResumeWorkout: { showingWorkout = workoutViewModel.isWorkoutActive },
                                onStartEmpty: {
                                    Task {
                                        await workoutViewModel.startAdHocSession()
                                        showingWorkout = workoutViewModel.isWorkoutActive
                                    }
                                },
                                onSelectTemplate: { showingTemplateList = true },
                                onOpenHistory: { showingWorkoutOverview = true }
                            )

                            TodayMomentumSection(
                                snapshot: viewModel.todayMomentumSnapshot,
                                onOpenScoreInsight: { selectedInsight = momentumInsight },
                                onOpenStreakInsight: { selectedInsight = streakInsight },
                                onOpenConsistencyInsight: { selectedInsight = consistencyInsight },
                                onOpenWeeklyInsight: { selectedInsight = weeklyInsight }
                            )
                        }

                        WorkoutCalendarSection(
                            monthTitle: viewModel.displayedMonthTitle,
                            monthSummary: viewModel.displayedMonthSummary,
                            currentStreakDays: viewModel.currentStreakDays,
                            weekdaySymbols: viewModel.weekdaySymbols,
                            days: viewModel.monthGridDays,
                            onPreviousMonth: {
                                Task { await viewModel.showPreviousMonth() }
                            },
                            onNextMonth: {
                                Task { await viewModel.showNextMonth() }
                            },
                            onOpenStreakInsight: { selectedInsight = streakInsight },
                            onOpenGoalInsight: { selectedInsight = goalInsight },
                            onOpenRateInsight: { selectedInsight = rateInsight },
                            onOpenDay: { day in
                                Task {
                                    if day.summary != nil {
                                        await viewModel.loadHistory(for: day.date)
                                        selectedHistoryDate = day.date
                                    } else if day.isPlannedWorkout,
                                              let preview = await viewModel.previewPlan(for: day.date) {
                                        selectedPlannedPreview = preview
                                    }
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.refresh()
            }
            .onChange(of: workoutViewModel.isWorkoutActive) { _, isActive in
                if !isActive {
                    showingWorkout = false
                    Task {
                        await viewModel.refresh()
                    }
                }
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
            .sheet(item: $selectedPlannedPreview) { preview in
                PlannedWorkoutPreviewSheet(preview: preview)
            }
            .sheet(item: $selectedInsight) { insight in
                TodayInsightSheet(insight: insight)
            }
            .fullScreenCover(isPresented: $showingLockedPlanPaywall) {
                if let lockedPlanSummary {
                    PaywallView(
                        planSummary: lockedPlanSummary,
                        allowsSkip: true,
                        showsCloseButton: true,
                        onSkip: {
                            showingLockedPlanPaywall = false
                        },
                        onPurchaseSuccess: {
                            Task {
                                await sessionViewModel.completePremiumUnlock()
                                showingLockedPlanPaywall = false
                            }
                        }
                    )
                }
            }
            .alert("Today", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .navigationDestination(isPresented: $showingWorkout) {
                LiveWorkoutView()
                    .environmentObject(workoutViewModel)
                    .onDisappear {
                        if !workoutViewModel.isWorkoutActive {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                    }
            }
        }
    }

    private var lockedPlanSummary: OnboardingPlanSummary? {
        sessionViewModel.onboardingPlanSummary
    }

    private var hasPremiumAccess: Bool {
        storeManager.isPremium || (sessionViewModel.currentUser?.isPremiumActive ?? false)
    }

    private func startTodayWorkout() {
        if workoutViewModel.isWorkoutActive {
            showingWorkout = true
            return
        }

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
            shuffleMessage = await viewModel.shuffleTodayPlan()
        }
    }

    private func openTodayHistory() {
        Task {
            await viewModel.loadHistory(for: viewModel.today)
            selectedHistoryDate = viewModel.today
        }
    }

    private var heroMode: TodayHeroMode {
        if workoutViewModel.isWorkoutActive {
            return .active
        }
        if viewModel.hasCompletedWorkoutToday {
            return .completed
        }
        if viewModel.todaySchedule?.isRestDay == true {
            return .rest
        }
        if viewModel.todayPlan != nil || viewModel.todaySchedule?.template != nil {
            return .planned
        }
        return .empty
    }

    private var shouldSurfaceMomentumBeforeQuickActions: Bool {
        heroMode == .completed || heroMode == .active
    }

    private var statusInsight: TodayInsightPayload {
        let scheduledTitle = viewModel.todayPlan?.template.name ?? viewModel.todaySchedule?.template?.name ?? "No template"
        let exercises = "\(viewModel.todayPlan?.exercises.count ?? 0)"

        switch heroMode {
        case .completed:
            return TodayInsightPayload(
                emoji: "✅",
                title: "Today Status",
                headline: "Completed and logged",
                message: "You already closed the loop today. Review the session details, check your streak, or go again if you want another round.",
                tint: .green,
                metrics: [
                    TodayInsightMetric(label: "Sessions", value: "\(viewModel.todayCompletedSessions.count)", tint: .green),
                    TodayInsightMetric(label: "XP Today", value: "+\(viewModel.todayMomentumSnapshot.todayXP)", tint: .green),
                    TodayInsightMetric(label: "Template", value: scheduledTitle, tint: .green),
                    TodayInsightMetric(label: "Streak", value: "\(viewModel.currentStreakDays)d", tint: .orange)
                ]
            )
        case .active:
            return TodayInsightPayload(
                emoji: "⚡️",
                title: "Today Status",
                headline: "Workout live right now",
                message: "You are mid-session. The fastest path is to jump back in, keep the pace high and convert this into a clean completed day.",
                tint: .orange,
                metrics: [
                    TodayInsightMetric(label: "Mode", value: "Live", tint: .orange),
                    TodayInsightMetric(label: "Template", value: scheduledTitle, tint: .orange),
                    TodayInsightMetric(label: "Planned", value: "\(viewModel.todayPlan?.exercises.count ?? 0) lifts", tint: .orange),
                    TodayInsightMetric(label: "Streak", value: "\(viewModel.currentStreakDays)d", tint: .orange)
                ]
            )
        case .planned:
            return TodayInsightPayload(
                emoji: "🔵",
                title: "Today Status",
                headline: "To Do and ready",
                message: "Today is still open. Your split is loaded, the workout order is generated and you can start immediately or swap into another template.",
                tint: .blue,
                metrics: [
                    TodayInsightMetric(label: "Status", value: "To Do", tint: .blue),
                    TodayInsightMetric(label: "Template", value: scheduledTitle, tint: .blue),
                    TodayInsightMetric(label: "Exercises", value: exercises, tint: .blue),
                    TodayInsightMetric(label: "Goal", value: "\(viewModel.displayedMonthSummary.activeDays)/\(max(1, viewModel.displayedMonthSummary.expectedWorkouts))", tint: .blue)
                ]
            )
        case .empty:
            return TodayInsightPayload(
                emoji: "🧩",
                title: "Today Status",
                headline: "Open day",
                message: "Nothing is fixed yet. Start freestyle or pick a template to turn this into a tracked gym day.",
                tint: .blue,
                metrics: [
                    TodayInsightMetric(label: "Status", value: "Open", tint: .blue),
                    TodayInsightMetric(label: "Sessions", value: "0", tint: .blue),
                    TodayInsightMetric(label: "Quick Start", value: "Freestyle", tint: .blue),
                    TodayInsightMetric(label: "This Week", value: "\(viewModel.todayMomentumSnapshot.weeklySessions)", tint: .blue)
                ]
            )
        case .rest:
            return TodayInsightPayload(
                emoji: "🛌",
                title: "Today Status",
                headline: "Recovery built in",
                message: "Today is marked as rest. Keep recovery clean or override it with a freestyle session if you still want to train.",
                tint: .orange,
                metrics: [
                    TodayInsightMetric(label: "Status", value: "Rest", tint: .orange),
                    TodayInsightMetric(label: "Streak", value: "\(viewModel.currentStreakDays)d", tint: .orange),
                    TodayInsightMetric(label: "This Week", value: "\(viewModel.todayMomentumSnapshot.weeklySessions)", tint: .orange),
                    TodayInsightMetric(label: "Goal", value: "\(viewModel.displayedMonthSummary.activeDays)/\(max(1, viewModel.displayedMonthSummary.expectedWorkouts))", tint: .orange)
                ]
            )
        }
    }

    private var streakInsight: TodayInsightPayload {
        let snapshot = viewModel.todayMomentumSnapshot

        return TodayInsightPayload(
            emoji: "🔥",
            title: "Streak",
            headline: snapshot.streakDays > 0 ? "\(snapshot.streakDays)-day streak live" : "Start the streak today",
            message: "Streaks are built by stacking completed days without gaps. The best UX move here is brutal simplicity: protect momentum and make the next session obvious.",
            tint: .orange,
            metrics: [
                TodayInsightMetric(label: "Current", value: "\(snapshot.streakDays)d", tint: .orange),
                TodayInsightMetric(label: "This Week", value: "\(snapshot.weeklySessions)", tint: .orange),
                TodayInsightMetric(label: "Month", value: "\(snapshot.monthlyActiveDays) days", tint: .green),
                TodayInsightMetric(label: "XP Today", value: "+\(snapshot.todayXP)", tint: .orange)
            ]
        )
    }

    private var goalInsight: TodayInsightPayload {
        let summary = viewModel.displayedMonthSummary

        return TodayInsightPayload(
            emoji: "🎯",
            title: "Monthly Goal",
            headline: summary.expectedWorkouts > 0
                ? "\(summary.activeDays) of \(summary.expectedWorkouts) scheduled days hit"
                : "\(summary.activeDays) active days logged",
            message: "Blue means still on the board. Green means closed. Red means a scheduled slot slipped by. This is the cleanest way to see whether your month is actually on track.",
            tint: .blue,
            metrics: [
                TodayInsightMetric(label: "Active Days", value: "\(summary.activeDays)", tint: .green),
                TodayInsightMetric(label: "Expected", value: "\(summary.expectedWorkouts)", tint: .blue),
                TodayInsightMetric(label: "Remaining", value: "\(summary.remainingScheduledWorkouts)", tint: .blue),
                TodayInsightMetric(label: "Missed", value: "\(summary.missedWorkouts)", tint: .red)
            ]
        )
    }

    private var rateInsight: TodayInsightPayload {
        let summary = viewModel.displayedMonthSummary
        let percentage = Int((summary.consistency * 100).rounded())

        return TodayInsightPayload(
            emoji: "📈",
            title: "Consistency Rate",
            headline: "\(percentage)% hit rate this month",
            message: "This rate compares completed active days against scheduled opportunities. It is the quickest quality check on whether the plan is actually being executed.",
            tint: .green,
            metrics: [
                TodayInsightMetric(label: "Rate", value: "\(percentage)%", tint: .green),
                TodayInsightMetric(label: "Workouts", value: "\(summary.totalWorkouts)", tint: .green),
                TodayInsightMetric(label: "Active Days", value: "\(summary.activeDays)", tint: .green),
                TodayInsightMetric(label: "Missed", value: "\(summary.missedWorkouts)", tint: .red)
            ]
        )
    }

    private var momentumInsight: TodayInsightPayload {
        let snapshot = viewModel.todayMomentumSnapshot

        return TodayInsightPayload(
            emoji: snapshot.level >= 8 ? "👑" : (snapshot.level >= 5 ? "🔥" : "⚡️"),
            title: "Momentum Score",
            headline: "Level \(snapshot.level) \(snapshot.rankTitle)",
            message: "Momentum is your combined training pulse: active days, total sessions, streak pressure and today's earned XP. It is meant to feel rewarding without being noisy.",
            tint: .blue,
            metrics: [
                TodayInsightMetric(label: "Score", value: "\(snapshot.score)", tint: .blue),
                TodayInsightMetric(label: "Level", value: "\(snapshot.level)", tint: .orange),
                TodayInsightMetric(label: "Today XP", value: "+\(snapshot.todayXP)", tint: .green),
                TodayInsightMetric(label: "Next Level", value: "\(snapshot.nextLevelScore)", tint: .blue)
            ]
        )
    }

    private var consistencyInsight: TodayInsightPayload {
        let snapshot = viewModel.todayMomentumSnapshot
        let summary = viewModel.displayedMonthSummary

        return TodayInsightPayload(
            emoji: "🧊",
            title: "Consistency",
            headline: "\(Int((snapshot.monthlyConsistency * 100).rounded()))% month-to-date",
            message: "Consistency is about showing up on planned days, not just stacking random sessions. Blue days are still there to claim, red ones are the slips.",
            tint: .blue,
            metrics: [
                TodayInsightMetric(label: "Active Days", value: "\(snapshot.monthlyActiveDays)", tint: .green),
                TodayInsightMetric(label: "Scheduled", value: "\(summary.expectedWorkouts)", tint: .blue),
                TodayInsightMetric(label: "Remaining", value: "\(summary.remainingScheduledWorkouts)", tint: .blue),
                TodayInsightMetric(label: "Missed", value: "\(summary.missedWorkouts)", tint: .red)
            ]
        )
    }

    private var weeklyInsight: TodayInsightPayload {
        let snapshot = viewModel.todayMomentumSnapshot

        return TodayInsightPayload(
            emoji: "📆",
            title: "This Week",
            headline: "\(snapshot.weeklySessions) sessions in the current week",
            message: "Weekly count is the pace indicator. If the screen should feel elite, this number has to be effortless to read and one tap away from context.",
            tint: .blue,
            metrics: [
                TodayInsightMetric(label: "This Week", value: "\(snapshot.weeklySessions)", tint: .blue),
                TodayInsightMetric(label: "Today XP", value: "+\(snapshot.todayXP)", tint: .green),
                TodayInsightMetric(label: "Streak", value: "\(snapshot.streakDays)d", tint: .orange),
                TodayInsightMetric(label: "Month Workouts", value: "\(snapshot.monthlyWorkoutCount)", tint: .blue)
            ]
        )
    }
}

private struct TodayLockedPlanCard: View {
    @EnvironmentObject private var localization: LocalizationService

    let summary: OnboardingPlanSummary
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localization.localized("plan.ready.card.title"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(localization.localized("plan.ready.title"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(
                localization.localized(
                    "plan.ready.plan.detail",
                    localization.localized(summary.goalFocus.planTitleKey),
                    summary.sessionLengthMinutes
                )
            )
            .font(.body)
            .foregroundStyle(.white.opacity(0.84))

            Text(
                localization.localized(
                    "plan.ready.plan.line",
                    summary.trainingDaysPerWeek,
                    localization.localized(summary.planStyle.titleKey)
                )
            )
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)

            HStack(spacing: 10) {
                TodayLockedTag(label: localization.localized(summary.rotationStyle.titleKey))
                TodayLockedTag(label: localizedTodayExperienceLevel(summary.experienceLevel))
                TodayLockedTag(label: localization.localized("wizard.training_days.value", summary.trainingDaysPerWeek))
            }

            Button(action: onUnlock) {
                HStack {
                    Image(systemName: "crown.fill")
                    Text(localization.localized("paywall.cta.unlock"))
                        .fontWeight(.bold)
                    Spacer()
                    Text(localization.localized("profile.premium.title"))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
                .foregroundStyle(Color(red: 0.07, green: 0.11, blue: 0.09))
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.18, blue: 0.15),
                    Color(red: 0.10, green: 0.34, blue: 0.22),
                    Color(red: 0.18, green: 0.56, blue: 0.34),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }
}

private struct TodayLockedTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.16), in: Capsule())
            .foregroundStyle(.white)
    }
}

@MainActor
private func localizedTodayExperienceLevel(_ rawLevel: String) -> String {
    let localization = LocalizationService.shared
    switch rawLevel {
    case "Beginner":
        return localization.localized("wizard.level.beginner")
    case "Advanced":
        return localization.localized("wizard.level.advanced")
    default:
        return localization.localized("wizard.level.intermediate")
    }
}

private extension OnboardingPlanStyle {
    var planStyleLabel: String {
        switch self {
        case .pushPull:
            return "Push / Pull"
        case .pushPullLegs:
            return "Push / Pull / Legs"
        case .pushPullLegsShoulders:
            return "Push / Pull / Legs / Shoulders"
        case .highFrequencyPushPullLegs:
            return "High Frequency PPL"
        }
    }
}

private struct TodayHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let schedule: ScheduleDay?
    let dayPlan: WorkoutDayPlanWithExercises?
    let completedSessions: [SessionWithDetails]
    let momentum: TodayMomentumSnapshot
    let shuffleUnavailableReason: String?
    let shuffleMessage: String?
    let hasActiveWorkout: Bool
    let activeExerciseName: String?
    let onPrimaryAction: () -> Void
    let onShuffle: () -> Void
    let onSelectTemplate: () -> Void
    let onOpenCompletedHistory: () -> Void
    let onOpenStatusInsight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: TodaySpacing.sm) {
                VStack(alignment: .leading, spacing: TodaySpacing.xs) {
                    HStack(spacing: 10) {
                        Button(action: onOpenStatusInsight) {
                            Text(heroAccentEmoji)
                                .font(.system(size: 24))
                                .frame(width: 42, height: 42)
                                .background(accentChipBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(secondaryTextColor)
                    }

                    Text(titleText)
                        .font(.system(size: heroMode == .completed ? 28 : 30, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryTextColor)
                        .contentTransition(.interpolate)
                        .lineLimit(2)

                    Text(subtitleText)
                        .font(.callout)
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(heroMode == .completed ? 2 : 3)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: TodaySpacing.xs) {
                    Button(action: onOpenStatusInsight) {
                        TodayHeroStatusPill(
                            title: statusTitle,
                            icon: statusIconName,
                            foreground: statusTint,
                            background: statusBadgeBackground
                        )
                    }
                    .buttonStyle(.plain)

                    if let statusDetailText {
                        Text(statusDetailText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            if heroMode == .completed, let completionSummary {
                completionSummarySection(summary: completionSummary)
            } else {
                HeroMomentumPillRow(
                    snapshot: momentum,
                    isCompleted: false,
                    isActive: heroMode == .active,
                    onOpenStreak: onOpenStatusInsight,
                    onOpenLevel: onOpenStatusInsight,
                    onOpenProgress: onOpenStatusInsight
                )

                if let dayPlan, !dayPlan.exercises.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TodaySpacing.xs) {
                            ForEach(dayPlan.exercises) { detail in
                                PlanExerciseChip(
                                    detail: detail,
                                    isCurrent: detail.exercise.name == activeExerciseName
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            actionArea
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .shadow(color: shadowColor, radius: 14, y: 6)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: heroMode)
    }

    private var heroMode: TodayHeroMode {
        if hasActiveWorkout {
            return .active
        }
        if !completedSessions.isEmpty {
            return .completed
        }
        if schedule?.isRestDay == true {
            return .rest
        }
        if dayPlan != nil || schedule?.template != nil {
            return .planned
        }
        return .empty
    }

    private var completionSummary: TodayCompletionSummary? {
        TodayCompletionSummary(sessions: completedSessions)
    }

    private var completedUsesDarkForeground: Bool {
        heroMode == .completed && colorScheme == .light
    }

    private var primaryTextColor: Color {
        switch heroMode {
        case .completed:
            return completedUsesDarkForeground ? Color.black.opacity(0.84) : .white.opacity(0.96)
        case .rest:
            return colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.82)
        default:
            return .white
        }
    }

    private var secondaryTextColor: Color {
        switch heroMode {
        case .completed:
            return completedUsesDarkForeground ? Color.black.opacity(0.62) : .white.opacity(0.76)
        case .rest:
            return colorScheme == .dark ? .white.opacity(0.72) : Color.black.opacity(0.62)
        default:
            return .white.opacity(0.78)
        }
    }

    private var statusTint: Color {
        switch heroMode {
        case .completed:
            return colorScheme == .dark ? Color.green.opacity(0.94) : Color.green.opacity(0.92)
        case .active:
            return Color.orange.opacity(0.96)
        case .planned, .empty:
            return Color.blue.opacity(0.96)
        case .rest:
            return Color.orange.opacity(0.90)
        }
    }

    private var accentChipBackground: Color {
        switch heroMode {
        case .completed:
            return colorScheme == .dark ? Color.green.opacity(0.22) : Color.white.opacity(0.64)
        case .active:
            return Color.orange.opacity(0.22)
        case .planned, .empty:
            return Color.blue.opacity(0.22)
        case .rest:
            return colorScheme == .dark ? Color.orange.opacity(0.18) : Color.white.opacity(0.56)
        }
    }

    private var statusBadgeBackground: Color {
        switch heroMode {
        case .completed:
            return colorScheme == .dark ? Color.green.opacity(0.18) : Color.white.opacity(0.82)
        case .active:
            return Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.16)
        case .planned, .empty:
            return Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.16)
        case .rest:
            return Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }
    }

    private var statusIconName: String {
        switch heroMode {
        case .completed:
            return "checkmark.circle.fill"
        case .active:
            return "bolt.circle.fill"
        case .planned:
            return "list.bullet.circle.fill"
        case .empty:
            return "plus.circle.fill"
        case .rest:
            return "bed.double.fill"
        }
    }

    private var shadowColor: Color {
        if heroMode == .completed {
            return colorScheme == .dark ? Color.black.opacity(0.24) : Color.green.opacity(0.18)
        }
        return Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10)
    }

    private var statusDetailText: String? {
        switch heroMode {
        case .active:
            return dayPlan.map { "\($0.exercises.count) exercises" }
        case .completed:
            guard let completionSummary else { return nil }
            return completionSummary.sessionCount == 1 ? "1 session logged" : "\(completionSummary.sessionCount) sessions logged"
        case .rest, .empty:
            return nil
        case .planned:
            return dayPlan.map { "\($0.exercises.count) exercises" }
        }
    }

    @ViewBuilder
    private var heroBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        switch heroMode {
        case .completed:
            shape
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(red: 0.08, green: 0.23, blue: 0.16),
                                Color(red: 0.09, green: 0.31, blue: 0.21),
                                Color(red: 0.10, green: 0.39, blue: 0.24)
                            ]
                            : [
                                Color(red: 0.86, green: 0.98, blue: 0.90),
                                Color(red: 0.66, green: 0.93, blue: 0.76),
                                Color(red: 0.44, green: 0.82, blue: 0.61)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.24))
                        .frame(width: 180, height: 180)
                        .blur(radius: 12)
                        .offset(x: 56, y: -72)
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.32), lineWidth: 1)
                }
        case .active:
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.16, blue: 0.09),
                            Color(red: 0.56, green: 0.22, blue: 0.12),
                            Color(red: 0.78, green: 0.38, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(shape)
        case .planned, .empty:
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.20, blue: 0.44),
                            Color(red: 0.14, green: 0.34, blue: 0.68),
                            Color(red: 0.17, green: 0.47, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(shape)
        case .rest:
            shape
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(red: 0.21, green: 0.18, blue: 0.13),
                                Color(red: 0.28, green: 0.22, blue: 0.14),
                                Color(red: 0.34, green: 0.26, blue: 0.17)
                            ]
                            : [
                                Color(red: 0.96, green: 0.90, blue: 0.80),
                                Color(red: 0.92, green: 0.84, blue: 0.72),
                                Color(red: 0.88, green: 0.76, blue: 0.61)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(shape)
        }
    }

    private var heroAccentEmoji: String {
        switch heroMode {
        case .active:
            return "⚡️"
        case .completed:
            return "🔥"
        case .rest:
            return "🛌"
        case .planned:
            return "🔵"
        case .empty:
            return "🧩"
        }
    }

    private var titleText: String {
        switch heroMode {
        case .active:
            return dayPlan?.template.name ?? "Workout in Progress"
        case .completed:
            return completionSummary?.titleText ?? "Workout Complete"
        case .rest:
            return "Recovery Day"
        case .planned:
            if let dayPlan {
                return dayPlan.template.name
            }
            if let template = schedule?.template {
                return template.name
            }
            return "Workout Ready"
        case .empty:
            return "No Workout Scheduled"
        }
    }

    private var subtitleText: String {
        switch heroMode {
        case .active:
            if let activeExerciseName {
                return "Resume where you left off. Current exercise: \(activeExerciseName)."
            }
            return "Resume your current workout without losing set progress."
        case .completed:
            return completionSummary?.subtitleText ?? "You already put work in today. Review the session or start another round."
        case .rest:
            return "Keep the streak alive tomorrow. Mobility, steps, and recovery count."
        case .planned:
            if let dayPlan {
                let anchors = dayPlan.exercises.filter { $0.planExercise.isAnchor }.map(\.exercise.name)
                if anchors.isEmpty {
                    return "\(dayPlan.exercises.count) exercises ready for today."
                }
                return "Anchors today: \(anchors.joined(separator: " • "))"
            }
            return "Pick a template or start an empty session when you want to train freestyle."
        case .empty:
            return "Pick a template or start an empty session when you want to train freestyle."
        }
    }

    private var statusTitle: String {
        switch heroMode {
        case .active:
            return "Live"
        case .completed:
            return "Completed"
        case .rest:
            return "Rest"
        case .planned:
            return "To Do"
        case .empty:
            return "Open"
        }
    }

    @ViewBuilder
    private func completionSummarySection(summary: TodayCompletionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HeroMomentumPillRow(
                snapshot: momentum,
                isCompleted: true,
                isActive: false,
                usesDarkForeground: completedUsesDarkForeground,
                totalSets: summary.totalSets,
                onOpenStreak: onOpenStatusInsight,
                onOpenLevel: onOpenStatusInsight,
                onOpenProgress: onOpenStatusInsight
            )

            FeaturedCompletedSessionCard(session: summary.latestSession, action: onOpenCompletedHistory)
        }
    }

    private var completedSecondaryActionTitle: String {
        if dayPlan != nil || schedule?.template != nil {
            return "Train Again"
        }
        return "New Session"
    }

    private var completedSecondaryActionIcon: String {
        if dayPlan != nil || schedule?.template != nil {
            return "figure.strengthtraining.traditional"
        }
        return "plus.circle.fill"
    }

    @ViewBuilder
    private var actionArea: some View {
        switch heroMode {
        case .active:
            Button(action: onPrimaryAction) {
                Label("Resume Workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(Color.black.opacity(0.84))
            }
        case .completed:
            HStack(spacing: 12) {
                Button(action: onOpenCompletedHistory) {
                    Label("View Sessions", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(completedUsesDarkForeground ? Color.white.opacity(0.88) : .white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(completedUsesDarkForeground ? Color.black.opacity(0.82) : .white.opacity(0.94))
                }

                Button(action: onPrimaryAction) {
                    Label(completedSecondaryActionTitle, systemImage: completedSecondaryActionIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(completedUsesDarkForeground ? 0.24 : 0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(completedUsesDarkForeground ? Color.black.opacity(0.78) : .white.opacity(0.90))
                }
            }
        case .rest:
            Button(action: onSelectTemplate) {
                Label("Train Anyway", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        case .empty:
            Button(action: onSelectTemplate) {
                Label("Choose Template", systemImage: "rectangle.grid.2x2.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        case .planned:
            HStack(spacing: 12) {
                Button(action: onPrimaryAction) {
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

            if let statusMessage = shuffleMessage ?? shuffleUnavailableReason, dayPlan != nil {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private struct TodayCompletionSummary {
        let sessions: [SessionWithDetails]

        init?(sessions: [SessionWithDetails]) {
            guard !sessions.isEmpty else { return nil }
            self.sessions = sessions.sorted {
                ($0.session.completedAt ?? $0.session.startedAt) > ($1.session.completedAt ?? $1.session.startedAt)
            }
        }

        var latestSession: SessionWithDetails {
            sessions[0]
        }

        var sessionCount: Int {
            sessions.count
        }

        var totalDuration: Int {
            sessions.reduce(0) { $0 + ($1.session.duration ?? 0) }
        }

        var totalSets: Int {
            sessions.reduce(0) { $0 + $1.totalSets }
        }

        var totalExercises: Int {
            sessions.reduce(0) { $0 + $1.exercisesCompleted }
        }

        var titleText: String {
            sessionCount == 1 ? "Workout Complete" : "\(sessionCount) Sessions Logged"
        }

        var subtitleText: String {
            let latestName = latestSession.template?.name ?? "Ad-hoc Workout"
            let completionTime = (latestSession.session.completedAt ?? latestSession.session.startedAt)
                .formatted(.dateTime.hour().minute())

            if sessionCount == 1 {
                if totalDuration > 0 {
                    return "\(latestName) · \(completionTime) · \(formatDuration(totalDuration))"
                }
                return "\(latestName) is logged for today."
            }

            if totalDuration > 0 {
                return "\(sessionCount) sessions · \(formatDuration(totalDuration)) total"
            }

            return "\(sessionCount) sessions are already logged today."
        }

        var totalDurationText: String {
            totalDuration > 0 ? formatDuration(totalDuration) : "Tracked"
        }

        var highlightSessions: [SessionWithDetails] {
            Array(sessions.prefix(3))
        }

        func nextActionText(hasScheduledTemplate: Bool) -> String? {
            if hasScheduledTemplate {
                return "Want more? Your scheduled template is still ready if you decide to go again."
            }
            return "Want more? Spin up another session without losing today's log."
        }
    }
}

private struct TodayHeroStatusPill: View {
    let title: String
    let icon: String?
    let foreground: Color
    let background: Color

    init(
        title: String,
        icon: String? = nil,
        foreground: Color = .white.opacity(0.92),
        background: Color = .white.opacity(0.14)
    ) {
        self.title = title
        self.icon = icon
        self.foreground = foreground
        self.background = background
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
            }
            Text(title)
                .font(.caption.weight(.bold))
        }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }
}

private struct HeroMomentumPillRow: View {
    let snapshot: TodayMomentumSnapshot
    let isCompleted: Bool
    let isActive: Bool
    var usesDarkForeground: Bool = false
    var totalSets: Int? = nil
    let onOpenStreak: () -> Void
    let onOpenLevel: () -> Void
    let onOpenProgress: () -> Void

    private var foregroundColor: Color {
        usesDarkForeground ? Color.black.opacity(0.74) : .white.opacity(0.90)
    }

    private var backgroundColor: Color {
        usesDarkForeground ? .white.opacity(0.34) : .white.opacity(0.12)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pillRow
            compactPillLayout
        }
    }

    private var pillRow: some View {
        HStack(spacing: 10) {
            streakPill(action: onOpenStreak)
            levelPill(action: onOpenLevel)
            progressPill(action: onOpenProgress)
            if isActive {
                livePill(action: onOpenLevel)
            }
        }
        .padding(.vertical, 2)
    }

    private var compactPillLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                streakPill(action: onOpenStreak)
                levelPill(action: onOpenLevel)
            }

            HStack(spacing: 10) {
                progressPill(action: onOpenProgress)
                if isActive {
                    livePill(action: onOpenLevel)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func streakPill(action: @escaping () -> Void) -> some View {
        HeroStatPill(
            emoji: "🔥",
            title: snapshot.streakDays > 0 ? "\(snapshot.streakDays)d streak" : "Start a streak",
            foreground: foregroundColor,
            background: backgroundColor,
            action: action
        )
    }

    private func levelPill(action: @escaping () -> Void) -> some View {
        HeroStatPill(
            emoji: "⚡️",
            title: "Lv \(snapshot.level) \(snapshot.rankTitle)",
            foreground: foregroundColor,
            background: backgroundColor,
            action: action
        )
    }

    private func progressPill(action: @escaping () -> Void) -> some View {
        HeroStatPill(
            emoji: isCompleted ? "✨" : "📆",
            title: isCompleted
                ? "+\(max(snapshot.todayXP, totalSets.map { $0 * 12 } ?? 0)) XP"
                : "\(snapshot.weeklySessions) this week",
            foreground: foregroundColor,
            background: backgroundColor,
            action: action
        )
    }

    private func livePill(action: @escaping () -> Void) -> some View {
        HeroStatPill(
            emoji: "🎧",
            title: "Live now",
            foreground: foregroundColor,
            background: backgroundColor,
            action: action
        )
    }
}

private struct HeroStatPill: View {
    let emoji: String
    let title: String
    let foreground: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 16))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}

private struct FeaturedCompletedSessionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: SessionWithDetails
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("🔥")
                            .font(.system(size: 16))
                        Text(session.session.startedAt, format: .dateTime.hour().minute())
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(primaryTextColor)

                    Text(session.template?.name ?? "Ad-hoc Workout")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(titleTextColor)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(session.session.formattedDuration)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(primaryTextColor)
                }

                HStack(spacing: 14) {
                    SessionMetricPill(symbol: "figure.strengthtraining.traditional", value: "\(session.exercisesCompleted)")
                    SessionMetricPill(symbol: "square.stack.3d.up", value: "\(session.totalSets)")
                    SessionMetricPill(symbol: "repeat", value: "\(session.totalReps)")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(colorScheme == .dark ? 0.10 : 0.24), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.36), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var titleTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color.black.opacity(0.82)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : Color.black.opacity(0.68)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : Color.black.opacity(0.60)
    }
}

private struct SessionMetricPill: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
            Text(value)
        }
    }
}

private struct TodayMomentumSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: TodayMomentumSnapshot
    let onOpenScoreInsight: () -> Void
    let onOpenStreakInsight: () -> Void
    let onOpenConsistencyInsight: () -> Void
    let onOpenWeeklyInsight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    Text("🔥")
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Momentum")
                            .font(.title3.weight(.bold))
                        Text("Keep the heat high.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onOpenScoreInsight) {
                    Text("Lv \(snapshot.level) ⚡️")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    MomentumFeatureCard(snapshot: snapshot, action: onOpenScoreInsight)
                    MomentumMiniCard(
                        title: "Streak",
                        value: snapshot.streakDays > 0 ? "\(snapshot.streakDays)" : "0",
                        caption: snapshot.streakDays == 1 ? "day live" : "days live",
                        emoji: "🔥",
                        colors: [Color(red: 1.0, green: 0.53, blue: 0.31), Color(red: 0.95, green: 0.30, blue: 0.36)],
                        action: onOpenStreakInsight
                    )
                    MomentumMiniCard(
                        title: "Consistency",
                        value: "\(Int((snapshot.monthlyConsistency * 100).rounded()))%",
                        caption: "\(snapshot.monthlyActiveDays) active days",
                        emoji: "🎯",
                        colors: [Color(red: 0.23, green: 0.55, blue: 1.0), Color(red: 0.31, green: 0.79, blue: 0.95)],
                        action: onOpenConsistencyInsight
                    )
                    MomentumMiniCard(
                        title: "This Week",
                        value: "\(snapshot.weeklySessions)",
                        caption: snapshot.weeklySessions == 1 ? "session" : "sessions",
                        emoji: "✨",
                        colors: [Color(red: 0.42, green: 0.83, blue: 0.49), Color(red: 0.20, green: 0.65, blue: 0.74)],
                        action: onOpenWeeklyInsight
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct MomentumFeatureCard: View {
    let snapshot: TodayMomentumSnapshot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 8) {
                        Text(rankEmoji)
                            .font(.system(size: 26))
                        Text(snapshot.rankTitle)
                            .font(.headline.weight(.bold))
                    }
                    Spacer()
                    Text("✨ +\(snapshot.todayXP) XP")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: Capsule())
                }

                Text("\(snapshot.score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Momentum score")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Next level")
                        Spacer()
                        Text("\(snapshot.nextLevelScore)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.14))
                            Capsule()
                                .fill(.white)
                                .frame(width: max(20, proxy.size.width * snapshot.progressToNextLevel))
                        }
                    }
                    .frame(height: 8)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(width: 220, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.13, blue: 0.24),
                        Color(red: 0.12, green: 0.31, blue: 0.52),
                        Color(red: 0.09, green: 0.64, blue: 0.69)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var rankEmoji: String {
        switch snapshot.level {
        case 1...2:
            return "🌱"
        case 3...4:
            return "⚡️"
        case 5...7:
            return "🔥"
        default:
            return "👑"
        }
    }
}

private struct MomentumMiniCard: View {
    let title: String
    let value: String
    let caption: String
    let emoji: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji)
                    .font(.system(size: 28))
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(width: 156, alignment: .leading)
            .frame(minHeight: 154, alignment: .leading)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: colors.last?.opacity(0.18) ?? .clear, radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct PlanExerciseChip: View {
    let detail: WorkoutDayPlanExerciseDetail
    let isCurrent: Bool

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
            .foregroundStyle(isCurrent ? .white.opacity(0.86) : .white.opacity(0.72))
        }
        .padding(12)
        .frame(width: 168, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isCurrent ? .white.opacity(0.22) : .white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isCurrent ? .white.opacity(0.30) : .clear, lineWidth: 1)
        )
        .foregroundStyle(.white)
    }
}

private struct TodayQuickActionsSection: View {
    let isWorkoutActive: Bool
    let onResumeWorkout: () -> Void
    let onStartEmpty: () -> Void
    let onSelectTemplate: () -> Void
    let onOpenHistory: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: TodaySpacing.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text("⚡️")
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Actions")
                            .font(.title3.weight(.bold))
                        Text("Fast lanes for whatever vibe you're on.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                if isWorkoutActive {
                    QuickActionTile(
                        title: "Resume",
                        subtitle: "Workout live now",
                        badge: "Live",
                        emoji: "⚡️",
                        tint: Color.green,
                        action: onResumeWorkout
                    )
                } else {
                    QuickActionTile(
                        title: "Freestyle",
                        subtitle: "Start from scratch",
                        badge: "Quick",
                        emoji: "🔥",
                        tint: Color.green,
                        action: onStartEmpty
                    )
                    QuickActionTile(
                        title: "Templates",
                        subtitle: "Launch your split",
                        badge: "Smart",
                        emoji: "🧠",
                        tint: Color.blue,
                        action: onSelectTemplate
                    )
                }
                QuickActionTile(
                    title: "History",
                    subtitle: "Replay wins",
                    badge: "Stats",
                    emoji: "🏆",
                    tint: Color.orange,
                    action: onOpenHistory
                )
            }
        }
    }
}

private struct QuickActionTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let badge: String
    let emoji: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(TodayPalette.elevatedSurface.opacity(colorScheme == .dark ? 0.72 : 0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Spacer()

                    Text(badge.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(TodayPalette.elevatedSurface.opacity(colorScheme == .dark ? 0.72 : 0.88), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint.opacity(0.86))
                }

                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(TodayPalette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.0 : 0.05), radius: 12, y: 6)
    }
}

private struct WorkoutCalendarSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let monthTitle: String
    let monthSummary: TodayMonthSummarySnapshot
    let currentStreakDays: Int
    let weekdaySymbols: [String]
    let days: [CalendarMonthDay]
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onOpenStreakInsight: () -> Void
    let onOpenGoalInsight: () -> Void
    let onOpenRateInsight: () -> Void
    let onOpenDay: (CalendarMonthDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("🔥")
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Consistency Board")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text("\(monthSummary.activeDays) active days • \(monthSummary.totalWorkouts) sessions")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            HStack(spacing: 10) {
                CalendarNavButton(icon: "chevron.left", action: onPreviousMonth)
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                CalendarNavButton(icon: "chevron.right", action: onNextMonth)
            }

            HStack(spacing: 10) {
                CalendarInsightBadge(
                    title: "Streak",
                    value: "\(currentStreakDays)d",
                    emoji: "🔥",
                    tint: Color.orange,
                    action: onOpenStreakInsight
                )
                CalendarInsightBadge(
                    title: "Goal",
                    value: monthSummary.expectedWorkouts > 0
                        ? "\(monthSummary.activeDays)/\(monthSummary.expectedWorkouts)"
                        : "\(monthSummary.activeDays)",
                    emoji: "🎯",
                    tint: Color.blue,
                    action: onOpenGoalInsight
                )
                CalendarInsightBadge(
                    title: "Rate",
                    value: "\(Int((monthSummary.consistency * 100).rounded()))%",
                    emoji: "📈",
                    tint: Color.green,
                    action: onOpenRateInsight
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Monthly progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((monthSummary.consistency * 100).rounded()))%")
                        .font(.caption.weight(.bold))
                }

                ProgressView(value: monthSummary.consistency)
                    .tint(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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

            Text("Green means done, blue shows upcoming sessions, red marks missed days. Tap any colored day to open history or preview what is coming next.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(TodayPalette.border.opacity(colorScheme == .dark ? 1 : 0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.0 : 0.05), radius: 18, y: 10)
    }
}

private struct CalendarInsightBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let emoji: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(emoji)
                    .font(.system(size: 20))
                Text(value)
                    .font(.subheadline.weight(.bold))
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TodayPalette.elevatedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.26 : 0.18), lineWidth: 1)
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarNavButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .frame(width: 32, height: 32)
                .background(TodayPalette.elevatedSurface, in: Circle())
                .overlay(
                    Circle()
                        .stroke(TodayPalette.border.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.0 : 0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarDayCell: View {
    @Environment(\.colorScheme) private var colorScheme

    let day: CalendarMonthDay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.subheadline.weight(day.isToday ? .bold : .semibold))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)

                if let summary = day.summary {
                    HStack(spacing: 6) {
                        Text("🔥")
                            .font(.system(size: 18))
                        if summary.workoutCount > 1 {
                            Text("x\(summary.workoutCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(textColor)
                        }
                    }
                } else if day.isMissedWorkout {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.red)
                } else if day.isPlannedWorkout {
                    Image(systemName: day.isToday ? "play.circle.fill" : "circle.fill")
                        .font(.system(size: day.isToday ? 18 : 12, weight: .bold))
                        .foregroundStyle(Color.blue)
                } else if day.isRestDay {
                    Text("🛌")
                        .font(.system(size: 16))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background {
                backgroundColor
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: day.isToday ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(day.summary == nil && !day.isPlannedWorkout)
    }

    @ViewBuilder
    private var backgroundColor: some View {
        if day.summary != nil {
            let activeTint = Color.green

            TodayPalette.elevatedSurface
                .overlay {
                    LinearGradient(
                        colors: [
                            activeTint.opacity(colorScheme == .dark ? 0.28 : 0.16),
                            activeTint.opacity(colorScheme == .dark ? 0.12 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        } else if day.isMissedWorkout {
            TodayPalette.elevatedSurface
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.red.opacity(colorScheme == .dark ? 0.30 : 0.16),
                            Color.red.opacity(colorScheme == .dark ? 0.14 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        } else if day.isPlannedWorkout {
            TodayPalette.elevatedSurface
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(colorScheme == .dark ? 0.28 : 0.16),
                            Color.blue.opacity(colorScheme == .dark ? 0.12 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        } else if day.isRestDay {
            TodayPalette.elevatedSurface
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.10),
                            Color.yellow.opacity(colorScheme == .dark ? 0.08 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        } else if day.isInDisplayedMonth {
            TodayPalette.elevatedSurface
        } else {
            TodayPalette.subduedSurface
        }
    }

    private var borderColor: Color {
        if day.isToday {
            if day.summary != nil {
                return Color.green.opacity(0.95)
            }
            if day.isPlannedWorkout {
                return Color.blue.opacity(0.95)
            }
            return Color.accentColor.opacity(0.92)
        }
        if day.summary != nil {
            return Color.green.opacity(0.20)
        }
        if day.isMissedWorkout {
            return Color.red.opacity(0.24)
        }
        if day.isPlannedWorkout {
            return Color.blue.opacity(0.20)
        }
        return .clear
    }

    private var textColor: Color {
        if day.summary != nil {
            return .primary
        }
        return day.isInDisplayedMonth ? .primary : .secondary
    }
}

private struct TodayScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TodayPalette.canvas
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.cyan.opacity(colorScheme == .dark ? 0.10 : 0.06))
                    .frame(width: 260, height: 260)
                    .blur(radius: 60)
                    .offset(x: -80, y: -120)
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.08 : 0.06))
                    .frame(width: 280, height: 280)
                    .blur(radius: 64)
                    .offset(x: 88, y: -74)
            }
    }
}

private struct PlannedWorkoutPreviewSheet: View {
    let preview: PlannedWorkoutPreview

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("🔵")
                                .font(.system(size: 30))
                                .frame(width: 54, height: 54)
                                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(preview.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(preview.plan.template.name)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 10) {
                            Label(preview.isPersistedPlan ? "Locked in" : "Smart preview", systemImage: preview.isPersistedPlan ? "checkmark.seal.fill" : "sparkles")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.10), in: Capsule())

                            Label(preview.goalFocus.title, systemImage: "target")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.indigo)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.10), in: Capsule())
                        }

                        Text(rotationHeadline)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    LazyVGrid(columns: columns, spacing: 12) {
                        PlannedWorkoutPreviewMetricCard(
                            emoji: "⏱️",
                            title: "Estimated",
                            value: "\(preview.estimatedDurationMinutes) min",
                            tint: Color.blue
                        )
                        PlannedWorkoutPreviewMetricCard(
                            emoji: "🏋️",
                            title: "Exercises",
                            value: "\(preview.plan.exercises.count)",
                            tint: Color.green
                        )
                        PlannedWorkoutPreviewMetricCard(
                            emoji: "⚓️",
                            title: "Anchors",
                            value: "\(preview.anchorExercises.count)",
                            tint: Color.orange
                        )
                        PlannedWorkoutPreviewMetricCard(
                            emoji: "🔁",
                            title: "Rotation",
                            value: preview.rotationStyle.title,
                            tint: Color.purple
                        )
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Workout line-up")
                            .font(.headline.weight(.bold))

                        ForEach(Array(preview.plan.exercises.enumerated()), id: \.element.id) { index, detail in
                            PlannedWorkoutExerciseRow(index: index + 1, detail: detail)
                        }
                    }
                    .padding(20)
                    .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What this means")
                            .font(.headline.weight(.bold))

                        Text(rotationFootnote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .padding(16)
            }
            .background(TodayPalette.canvas)
            .navigationTitle("Planned Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var rotationHeadline: String {
        if preview.isReusedBlock {
            return "This session stays in your current progression block, so the accessory work remains stable and measurable."
        }
        return "This is the next planned split for your week, ready to preview before the session actually starts."
    }

    private var rotationFootnote: String {
        if preview.rotationStyle.cadenceSessions == 1 {
            return "Your setup rotates supporting exercises every new session, while anchors still keep the split recognizable."
        }
        if preview.isReusedBlock {
            return "Your \(preview.rotationStyle.title.lowercased()) rotation keeps this assistance block for \(preview.rotationStyle.cadenceSessions) sessions before new variations kick in."
        }
        return "Your \(preview.rotationStyle.title.lowercased()) rotation starts a fresh assistance block here. That keeps the anchors progressing while support lifts refresh at the right time."
    }
}

private struct PlannedWorkoutPreviewMetricCard: View {
    let emoji: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emoji)
                .font(.system(size: 22))
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct PlannedWorkoutExerciseRow: View {
    let index: Int
    let detail: WorkoutDayPlanExerciseDetail

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.subheadline.weight(.bold))
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(detail.exercise.name)
                        .font(.subheadline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if detail.planExercise.isAnchor {
                        Text("Anchor")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    if let targetSets = detail.planExercise.targetSets {
                        Label("\(targetSets) sets", systemImage: "square.stack.3d.up")
                    }
                    if let targetReps = detail.planExercise.targetReps {
                        Label("\(targetReps) reps", systemImage: "repeat")
                    } else if let targetDuration = detail.planExercise.targetDuration {
                        Label("\(targetDuration / 60)m", systemImage: "clock")
                    }
                    if let targetWeight = detail.planExercise.targetWeight, targetWeight > 0 {
                        Label("\(Int(targetWeight)) kg", systemImage: "scalemass")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(TodayPalette.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TodayPalette.border, lineWidth: 1)
        )
    }
}

private struct TodayInsightSheet: View {
    let insight: TodayInsightPayload

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text(insight.emoji)
                                .font(.system(size: 34))
                                .frame(width: 58, height: 58)
                                .background(insight.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.title3.weight(.bold))
                                Text(insight.headline)
                                    .font(.headline)
                                    .foregroundStyle(insight.tint)
                            }
                        }

                        Text(insight.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(insight.metrics) { metric in
                            TodayInsightMetricCard(metric: metric)
                        }
                    }
                }
                .padding(16)
            }
            .background(TodayPalette.canvas)
            .navigationTitle(insight.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TodayInsightMetricCard: View {
    let metric: TodayInsightMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.value)
                .font(.title3.weight(.bold))
                .foregroundStyle(metric.tint)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
            Text(metric.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(16)
        .background(TodayPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(metric.tint.opacity(0.16), lineWidth: 1)
        )
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
