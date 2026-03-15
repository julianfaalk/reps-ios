import SwiftUI

private enum WorkoutSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

struct LiveWorkoutView: View {
    @EnvironmentObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddExercise = false
    @State private var showingAddCardio = false
    @State private var showingFinishConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var showingSessionSummary = false
    @State private var warmupCardioType: CardioType = .treadmill
    @State private var completedSession: SessionWithDetails?

    var body: some View {
        VStack(spacing: 0) {
            LiveWorkoutTopBar(
                duration: viewModel.formattedWorkoutDuration,
                isRestTimerActive: viewModel.isRestTimerActive,
                formattedRestTime: viewModel.formattedRestTime,
                onCancel: { showingCancelConfirmation = true },
                onAddExercise: { showingAddExercise = true },
                onAddCardio: { showingAddCardio = true },
                onFinishWorkout: { showingFinishConfirmation = true }
            )
            .padding(.horizontal, WorkoutSpacing.md)
            .padding(.top, WorkoutSpacing.xs)
            .padding(.bottom, WorkoutSpacing.xs)

            if viewModel.isRestTimerActive {
                RestTimerView(
                    timeRemaining: viewModel.restTimeRemaining,
                    totalTime: viewModel.restTimerTotalTime,
                    formattedTime: viewModel.formattedRestTime,
                    onDismiss: { viewModel.stopRestTimer() },
                    onAddTime: { seconds in viewModel.addRestTime(seconds) }
                )
                .padding(.horizontal, WorkoutSpacing.md)
                .padding(.bottom, WorkoutSpacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if let currentExercise = viewModel.currentExercise {
                    ExerciseLoggerView(
                        detail: currentExercise,
                        completedSets: viewModel.completedSetsForCurrentExercise,
                        lastEnteredValues: viewModel.getLastEnteredValues(for: currentExercise.exercise.id),
                        currentExerciseIndex: viewModel.currentExerciseIndex,
                        totalExercises: viewModel.templateExercises.count,
                        isLastExercise: viewModel.isLastExercise,
                        warmupCardioType: $warmupCardioType,
                        showWarmupPrompt: !viewModel.hasSatisfiedWarmupRequirement,
                        isLoggingEnabled: viewModel.hasSatisfiedWarmupRequirement,
                        loggingHint: viewModel.hasSatisfiedWarmupRequirement
                            ? nil
                            : viewModel.isWarmupTimerActive
                            ? "Finish or skip the 10-minute warm-up to unlock set tracking."
                            : "Start the 10-minute warm-up or skip it to unlock set tracking.",
                        isWarmupTimerActive: viewModel.isWarmupTimerActive,
                        warmupTimeRemaining: viewModel.warmupTimeRemaining,
                        warmupTimerTotalTime: viewModel.warmupTimerTotalTime,
                        formattedWarmupTime: viewModel.formattedWarmupTime,
                        onStartWarmup: { viewModel.startWarmupTimer(type: warmupCardioType) },
                        onSkipWarmup: { viewModel.skipWarmup() },
                        onLogSet: { reps, duration, weight in
                            viewModel.setLastEnteredValues(
                                for: currentExercise.exercise.id,
                                reps: reps,
                                weight: weight
                            )
                            Task {
                                await viewModel.logSet(reps: reps, duration: duration, weight: weight)
                            }
                        },
                        onDeleteSet: { set in
                            Task {
                                await viewModel.deleteSet(set)
                            }
                        },
                        onPrevious: { viewModel.previousExercise() },
                        onNext: { viewModel.nextExercise() },
                        onFinishWorkout: { showingFinishConfirmation = true },
                        onAddCardio: { showingAddCardio = true }
                    )
                    .id(currentExercise.id)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                } else if viewModel.templateExercises.isEmpty {
                    EmptyWorkoutView(
                        onAddExercise: { showingAddExercise = true },
                        onAddCardio: { showingAddCardio = true }
                    )
                } else {
                    WorkoutCompletedView(
                        totalExercises: viewModel.templateExercises.count,
                        totalSets: viewModel.completedSets.count,
                        onFinish: { showingFinishConfirmation = true },
                        onAddCardio: { showingAddCardio = true },
                        onAddExercise: { showingAddExercise = true }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exercise in
                viewModel.addExerciseToSession(exercise)
            }
        }
        .sheet(isPresented: $showingAddCardio) {
            AddCardioView(sessionId: viewModel.currentSession?.id ?? UUID()) { cardio in
                Task {
                    await viewModel.addCardioSession(cardio)
                }
            }
        }
        .sheet(isPresented: $showingSessionSummary) {
            if let session = completedSession {
                SessionSummaryView(
                    session: session,
                    newPRs: viewModel.newPRs,
                    onSaveNotes: { notes in
                        Task {
                            await viewModel.updateSessionNotes(session.session.id, notes)
                        }
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
            }
        }
        .alert("Finish Workout?", isPresented: $showingFinishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Finish") {
                Task {
                    if let session = await viewModel.completeSession() {
                        completedSession = session
                        showingSessionSummary = true
                    }
                }
            }
        } message: {
            Text("Are you done with this workout?")
        }
        .alert("Cancel Workout?", isPresented: $showingCancelConfirmation) {
            Button("Keep Working Out", role: .cancel) { }
            Button("Cancel Workout", role: .destructive) {
                viewModel.cancelSession()
                dismiss()
            }
        } message: {
            Text("This will discard all logged sets.")
        }
        .simultaneousGesture(exerciseSwipeGesture)
        .animation(.snappy(duration: 0.22), value: viewModel.isRestTimerActive)
        .animation(.snappy(duration: 0.22), value: viewModel.currentExerciseIndex)
        .animation(.snappy(duration: 0.22), value: viewModel.completedSets.count)
        .sensoryFeedback(.success, trigger: viewModel.completedSets.count)
    }

    private var exerciseSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if value.translation.width < -60 {
                    viewModel.nextExercise()
                } else if value.translation.width > 60 {
                    viewModel.previousExercise()
                }
            }
    }
}

private struct LiveWorkoutTopBar: View {
    let duration: String
    let isRestTimerActive: Bool
    let formattedRestTime: String
    let onCancel: () -> Void
    let onAddExercise: () -> Void
    let onAddCardio: () -> Void
    let onFinishWorkout: () -> Void

    var body: some View {
        HStack(spacing: WorkoutSpacing.sm) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 72, minHeight: 44)
                    .padding(.horizontal, WorkoutSpacing.xs)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("Workout")
                    .font(.headline.weight(.semibold))

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(duration)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)

                    if isRestTimerActive {
                        Text(formattedRestTime)
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Menu {
                Button(action: onAddExercise) {
                    Label("Add Exercise", systemImage: "dumbbell")
                }

                Button(action: onAddCardio) {
                    Label("Add Cardio", systemImage: "figure.run")
                }

                Divider()

                Button(action: onFinishWorkout) {
                    Label("Finish Workout", systemImage: "checkmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct RestTimerView: View {
    let timeRemaining: Int
    let totalTime: Int
    let formattedTime: String
    let onDismiss: () -> Void
    let onAddTime: (Int) -> Void

    private var progress: Double {
        guard totalTime > 0 else { return 0 }
        return Double(timeRemaining) / Double(totalTime)
    }

    private var progressColor: Color {
        if progress > 0.5 {
            return .green
        } else if progress > 0.25 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        HStack(spacing: WorkoutSpacing.md) {
            timerCircle(diameter: 104)

            VStack(alignment: .leading, spacing: WorkoutSpacing.sm) {
                HStack {
                    Text("Rest Timer")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(formattedTime)
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.orange)
                }

                HStack(spacing: WorkoutSpacing.xs) {
                    RestAdjustButton(label: "-10") { onAddTime(-10) }
                    RestAdjustButton(label: "+10") { onAddTime(10) }
                    RestAdjustButton(label: "+30") { onAddTime(30) }
                }

                Button(action: onDismiss) {
                    Label("Skip Rest", systemImage: "forward.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WorkoutSpacing.md)
        .padding(.vertical, WorkoutSpacing.sm)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func timerCircle(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 9)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            VStack(spacing: 2) {
                Text("Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(formattedTime)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct RestAdjustButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 64, height: 40)
                .background(Color(.systemBackground))
                .foregroundColor(.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct WarmupEntryPanel: View {
    @Binding var selectedType: CardioType
    @Binding var isExpanded: Bool
    let isTimerActive: Bool
    let timeRemaining: Int
    let totalTime: Int
    let formattedTime: String
    let onStartWarmup: () -> Void
    let onSkipWarmup: () -> Void

    private var progress: Double {
        guard totalTime > 0 else { return 0 }
        return 1 - (Double(timeRemaining) / Double(totalTime))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: WorkoutSpacing.sm) {
                if isTimerActive {
                    VStack(alignment: .leading, spacing: WorkoutSpacing.sm) {
                        HStack(alignment: .center, spacing: WorkoutSpacing.md) {
                            VStack(alignment: .leading, spacing: WorkoutSpacing.xxs) {
                                Text("Warm-up running")
                                    .font(.subheadline.weight(.semibold))

                                Text(formattedTime)
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }

                            Spacer()

                            Image(systemName: "timer")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 52, height: 52)
                                .background(Color.orange.opacity(0.12), in: Circle())
                        }

                        ProgressView(value: progress)
                            .tint(.orange)

                        Text("Set logging unlocks automatically when the 10-minute warm-up ends.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(action: onSkipWarmup) {
                            Label("Skip Warm-up", systemImage: "forward.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Text("Start with 10 minutes of light cardio to unlock set logging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Warm-up type", selection: $selectedType) {
                        ForEach(CardioType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: onStartWarmup) {
                        Label("Start 10-min Warm-up", systemImage: "figure.run")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    Button(action: onSkipWarmup) {
                        Text("Skip for now")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.top, WorkoutSpacing.sm)
        } label: {
            HStack {
                Label("10-min Warm-up", systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                if isTimerActive {
                    Text(formattedTime)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                } else {
                    Text("Required")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(WorkoutSpacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ExerciseLoggerView: View {
    let detail: TemplateExerciseDetail
    let completedSets: [SessionSet]
    let lastEnteredValues: (reps: Int?, weight: Double?)
    let currentExerciseIndex: Int
    let totalExercises: Int
    let isLastExercise: Bool
    @Binding var warmupCardioType: CardioType
    let showWarmupPrompt: Bool
    let isLoggingEnabled: Bool
    let loggingHint: String?
    let isWarmupTimerActive: Bool
    let warmupTimeRemaining: Int
    let warmupTimerTotalTime: Int
    let formattedWarmupTime: String
    let onStartWarmup: () -> Void
    let onSkipWarmup: () -> Void
    let onLogSet: (Int?, Int?, Double?) -> Void
    let onDeleteSet: (SessionSet) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onFinishWorkout: () -> Void
    let onAddCardio: () -> Void

    @State private var repsInput: String = ""
    @State private var durationInput: String = ""
    @State private var weightInput: String = ""
    @State private var hasInitialized = false
    @State private var showDetails = false
    @State private var warmupExpanded = true

    var exercise: Exercise { detail.exercise }
    var templateExercise: TemplateExercise { detail.templateExercise }

    private var equipmentIsBarbell: Bool {
        let eq = (exercise.equipment ?? "").lowercased()
        let barbellTerms = [
            "barbell", "langhantel", "sz",
            "bar", "stange",
            "ez bar", "curl bar",
            "olympia", "olympic",
            "straight bar", "gerade"
        ]
        return barbellTerms.contains { eq.contains($0) }
    }

    private var currentSetNumber: Int {
        completedSets.count + 1
    }

    private var targetSets: Int? {
        templateExercise.targetSets
    }

    private var isExerciseComplete: Bool {
        guard let targetSets else { return false }
        return completedSets.count >= targetSets
    }

    private var hasExerciseMeta: Bool {
        let hasNotes = !(exercise.notes?.isEmpty ?? true)
        let hasEquipment = !(exercise.equipment?.isEmpty ?? true)
        return hasNotes || hasEquipment
    }

    private var stateTitle: String {
        if !isLoggingEnabled {
            return "Warm-up"
        }
        if isExerciseComplete {
            return "Complete"
        }
        return "Current"
    }

    private var stateColor: Color {
        if !isLoggingEnabled {
            return .orange
        }
        if isExerciseComplete {
            return .green
        }
        return .accentColor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkoutSpacing.md) {
                if showWarmupPrompt {
                    WarmupEntryPanel(
                        selectedType: $warmupCardioType,
                        isExpanded: $warmupExpanded,
                        isTimerActive: isWarmupTimerActive,
                        timeRemaining: warmupTimeRemaining,
                        totalTime: warmupTimerTotalTime,
                        formattedTime: formattedWarmupTime,
                        onStartWarmup: onStartWarmup,
                        onSkipWarmup: onSkipWarmup
                    )
                }

                VStack(alignment: .leading, spacing: WorkoutSpacing.md) {
                    exerciseHeader

                    Divider()

                    currentSetEditor

                    if hasExerciseMeta {
                        Divider()

                        DisclosureGroup(isExpanded: $showDetails) {
                            VStack(alignment: .leading, spacing: WorkoutSpacing.xs) {
                                if let notes = exercise.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if let equipment = exercise.equipment, !equipment.isEmpty {
                                    Text("Equipment: \(equipment)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, WorkoutSpacing.sm)
                        } label: {
                            Label("Form cues & details", systemImage: "text.alignleft")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(WorkoutSpacing.md)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                if isLastExercise && isExerciseComplete {
                    VStack(alignment: .leading, spacing: WorkoutSpacing.sm) {
                        HStack {
                            Label("Workout finished", systemImage: "flag.checkered")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Spacer()
                            Text("All planned work is logged.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: WorkoutSpacing.sm) {
                            Button("Finish Workout", action: onFinishWorkout)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button("Add Cardio", action: onAddCardio)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(WorkoutSpacing.md)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else if isLastExercise {
                    Button(action: onAddCardio) {
                        HStack {
                            Label("Optional cardio finisher", systemImage: "figure.run")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                        .padding(WorkoutSpacing.md)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if !completedSets.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Logged Sets")
                                .font(.headline)
                            Spacer()
                            Text("\(completedSets.count)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(.systemBackground), in: Capsule())
                        }
                        .padding(.horizontal, WorkoutSpacing.md)
                        .padding(.vertical, WorkoutSpacing.sm)

                        Divider()

                        VStack(spacing: 0) {
                            ForEach(Array(completedSets.enumerated()), id: \.element.id) { index, set in
                                CompletedSetCompactRow(set: set, exerciseType: exercise.exerciseType)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            onDeleteSet(set)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }

                                if index < completedSets.count - 1 {
                                    Divider()
                                        .padding(.leading, WorkoutSpacing.md)
                                }
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, WorkoutSpacing.md)
            .padding(.top, WorkoutSpacing.sm)
            .padding(.bottom, 88)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomDock
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    hideKeyboard()
                }
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
        .onAppear {
            initializeInputs()
        }
        .onChange(of: detail.exercise.id) { _, _ in
            hasInitialized = false
            showDetails = false
            initializeInputs()
        }
    }

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: WorkoutSpacing.sm) {
            HStack(alignment: .top, spacing: WorkoutSpacing.sm) {
                VStack(alignment: .leading, spacing: WorkoutSpacing.xs) {
                    HStack(spacing: WorkoutSpacing.xs) {
                        Text("\(min(currentExerciseIndex + 1, max(totalExercises, 1))) / \(max(totalExercises, 1))")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Text(stateTitle)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(stateColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(stateColor)
                    }

                    Text(exercise.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    if !exercise.muscleGroups.isEmpty {
                        Text(exercise.muscleGroups.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: WorkoutSpacing.xs) {
                    navButton(
                        systemImage: "chevron.left",
                        isEnabled: currentExerciseIndex > 0,
                        action: onPrevious
                    )

                    navButton(
                        systemImage: isLastExercise ? "flag.checkered" : "chevron.right",
                        isEnabled: !isLastExercise,
                        action: onNext
                    )
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WorkoutSpacing.xs) {
                    if let sets = templateExercise.targetSets {
                        ExerciseMetricChip(value: "\(sets)", label: "Sets")
                    }

                    if exercise.exerciseType == .reps, let reps = templateExercise.targetReps {
                        ExerciseMetricChip(value: "\(reps)", label: "Reps")
                    }

                    if exercise.exerciseType == .timed, let duration = templateExercise.targetDuration {
                        ExerciseMetricChip(value: formatDuration(duration), label: "Time")
                    }

                    if let weight = templateExercise.targetWeight {
                        ExerciseMetricChip(value: weight.formattedWeight, label: "Weight")
                    }
                }
            }
        }
    }

    private var currentSetEditor: some View {
        VStack(alignment: .leading, spacing: WorkoutSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: WorkoutSpacing.xs) {
                Text("Set \(currentSetNumber)")
                    .font(.title3.weight(.bold))

                if let targetSets {
                    Text(isExerciseComplete ? "Target reached" : "of \(targetSets)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isExerciseComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: WorkoutSpacing.sm) {
                if exercise.exerciseType == .reps {
                    LoggerInputField(
                        title: "Reps",
                        text: $repsInput,
                        keyboardType: .numberPad
                    )

                    LoggerInputField(
                        title: equipmentIsBarbell ? "Total kg" : "Weight",
                        text: $weightInput,
                        keyboardType: .decimalPad
                    )
                } else {
                    LoggerInputField(
                        title: "Seconds",
                        text: $durationInput,
                        keyboardType: .numberPad
                    )

                    LoggerInputField(
                        title: "Weight",
                        text: $weightInput,
                        keyboardType: .decimalPad
                    )
                }
            }

            if equipmentIsBarbell {
                VStack(spacing: WorkoutSpacing.xxs) {
                    Text("Total barbell weight")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let weight = parseDecimal(weightInput), weight >= 20 {
                        let perSide = (weight - 20) / 2
                        Text("20 kg bar + \(String(format: "%.1f", perSide)) kg per side")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if isExerciseComplete && !isLastExercise {
                HStack(spacing: WorkoutSpacing.xs) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("The next exercise opens automatically when you hit the target sets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var bottomDock: some View {
        VStack(spacing: WorkoutSpacing.sm) {
            if let loggingHint, !loggingHint.isEmpty {
                Text(loggingHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: logCurrentSet) {
                Label("Log Set", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        isLoggingEnabled ? Color.accentColor : Color.accentColor.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .foregroundStyle(.white)
            }
            .disabled(!isLoggingEnabled)
        }
        .padding(.horizontal, WorkoutSpacing.md)
        .padding(.top, WorkoutSpacing.xs)
        .padding(.bottom, WorkoutSpacing.xs)
        .background(Color.clear)
    }

    private func navButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 36)
                .background(Color(.systemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
    }

    private func initializeInputs() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let lastReps = lastEnteredValues.reps {
            repsInput = "\(lastReps)"
        } else if let reps = templateExercise.targetReps {
            repsInput = "\(reps)"
        }

        if let duration = templateExercise.targetDuration {
            durationInput = "\(duration)"
        }

        if let lastWeight = lastEnteredValues.weight {
            weightInput = lastWeight.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(lastWeight))"
                : String(format: "%.1f", lastWeight)
        } else if let weight = templateExercise.targetWeight {
            weightInput = weight.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(weight))"
                : String(format: "%.1f", weight)
        }
    }

    private func logCurrentSet() {
        hideKeyboard()

        let reps = exercise.exerciseType == .reps ? Int(repsInput) : nil
        let duration = exercise.exerciseType == .timed ? Int(durationInput) : nil
        let weight = parseDecimal(weightInput)

        onLogSet(reps, duration, weight)
    }
}

private struct ExerciseMetricChip: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, WorkoutSpacing.sm)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: Capsule())
    }
}

private struct LoggerInputField: View {
    let title: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: WorkoutSpacing.xs) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            TextField("0", text: $text)
                .keyboardType(keyboardType)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompletedSetCompactRow: View {
    let set: SessionSet
    let exerciseType: ExerciseType

    var body: some View {
        HStack(spacing: WorkoutSpacing.sm) {
            VStack(alignment: .leading, spacing: WorkoutSpacing.xxs) {
                Text("Set \(set.setNumber)")
                    .font(.subheadline.weight(.semibold))
                Text(set.completedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if exerciseType == .reps, let reps = set.reps {
                valueChip("\(reps)", label: "reps")
            } else if exerciseType == .timed, let duration = set.duration {
                valueChip(formatDuration(duration), label: "time")
            }

            if let weight = set.weight {
                valueChip(weight.formattedWeight, label: "weight")
            }

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(.horizontal, WorkoutSpacing.md)
        .padding(.vertical, WorkoutSpacing.sm)
    }

    private func valueChip(_ value: String, label: String) -> some View {
        VStack(spacing: WorkoutSpacing.xxs) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyWorkoutView: View {
    let onAddExercise: () -> Void
    let onAddCardio: () -> Void

    var body: some View {
        VStack(spacing: WorkoutSpacing.md) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)

            Text("This session is empty.")
                .font(.title3.weight(.bold))

            Text("Add an exercise or cardio block to start logging.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: WorkoutSpacing.sm) {
                Button(action: onAddExercise) {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                }

                Button(action: onAddCardio) {
                    Label("Add Cardio", systemImage: "figure.run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(WorkoutSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkoutCompletedView: View {
    let totalExercises: Int
    let totalSets: Int
    let onFinish: () -> Void
    let onAddCardio: () -> Void
    let onAddExercise: () -> Void

    var body: some View {
        VStack(spacing: WorkoutSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.green)

            Text("Workout Complete")
                .font(.title2.weight(.bold))

            Text("\(totalExercises) exercises and \(totalSets) logged sets are ready to save.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onFinish) {
                Text("Finish Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }

            HStack(spacing: WorkoutSpacing.sm) {
                Button(action: onAddCardio) {
                    Label("Cardio", systemImage: "figure.run")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button(action: onAddExercise) {
                    Label("Extra Exercise", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(WorkoutSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
