import SwiftUI

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
    @State private var shuffleMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Workout Timer
                WorkoutTimerBar(
                    duration: viewModel.formattedWorkoutDuration,
                    isRestTimerActive: viewModel.isRestTimerActive,
                    restTimeRemaining: viewModel.formattedRestTime
                )

                // Rest Timer Overlay
                if viewModel.isRestTimerActive {
                    RestTimerView(
                        timeRemaining: viewModel.restTimeRemaining,
                        totalTime: viewModel.restTimerTotalTime,
                        formattedTime: viewModel.formattedRestTime,
                        onDismiss: { viewModel.stopRestTimer() },
                        onAddTime: { seconds in viewModel.addRestTime(seconds) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Main content
                Group {
                    if let currentExercise = viewModel.currentExercise {
                        VStack(spacing: 10) {
                            if !viewModel.currentPlanExercises.isEmpty {
                                WorkoutPlanPreviewCard(
                                    exercises: viewModel.currentPlanExercises,
                                    canShuffle: viewModel.canShuffleCurrentWorkout,
                                    message: shuffleMessage ?? (viewModel.currentDayPlan != nil && !viewModel.canShuffleCurrentWorkout
                                        ? "Plan locked after the first logged set."
                                        : nil),
                                    onShuffle: {
                                        Task {
                                            shuffleMessage = await viewModel.shuffleCurrentWorkout()
                                        }
                                    }
                                )
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                            }

                            if !viewModel.hasLoggedWarmup {
                                WarmupCardioPrompt(
                                    selectedType: $warmupCardioType,
                                    onAddWarmup: {
                                        Task {
                                            await viewModel.addWarmupCardio(type: warmupCardioType)
                                        }
                                    }
                                )
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                            }

                            CurrentExerciseView(
                                detail: currentExercise,
                                completedSets: viewModel.completedSetsForCurrentExercise,
                                lastEnteredValues: viewModel.getLastEnteredValues(for: currentExercise.exercise.id),
                                isLoggingEnabled: viewModel.hasLoggedWarmup,
                                loggingHint: viewModel.hasLoggedWarmup
                                    ? nil
                                    : "Bitte zuerst 10 Min Warm-up Cardio starten.",
                                onLogSet: { reps, duration, weight in
                                    // Save last entered values for this exercise
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
                                }
                            )

                            if viewModel.isLastExercise {
                                FinisherCardioPrompt {
                                    showingAddCardio = true
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                            }
                        }
                    } else if viewModel.templateExercises.isEmpty {
                        EmptyWorkoutView(
                            onAddExercise: { showingAddExercise = true },
                            onAddCardio: { showingAddCardio = true }
                        )
                    } else {
                        WorkoutCompletedView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                WorkoutNavigationBar(
                    currentIndex: viewModel.currentExerciseIndex,
                    totalExercises: viewModel.templateExercises.count,
                    onPrevious: { viewModel.previousExercise() },
                    onNext: { viewModel.nextExercise() },
                    onSkip: { viewModel.skipExercise() },
                    isFirstExercise: viewModel.currentExerciseIndex == 0,
                    isLastExercise: viewModel.isLastExercise
                )
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isRestTimerActive)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCancelConfirmation = true
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddExercise = true
                        } label: {
                            Label("Add Exercise", systemImage: "dumbbell")
                        }

                        Button {
                            showingAddCardio = true
                        } label: {
                            Label("Add Cardio", systemImage: "figure.run")
                        }

                        Divider()

                        Button {
                            showingFinishConfirmation = true
                        } label: {
                            Label("Finish Workout", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
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
        }
    }
}

struct WorkoutTimerBar: View {
    let duration: String
    let isRestTimerActive: Bool
    let restTimeRemaining: String

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(duration)
                    .font(.headline)
                    .monospacedDigit()
            }
            .foregroundColor(.white)

            Spacer()

            if isRestTimerActive {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                    Text(restTimeRemaining)
                        .font(.headline)
                        .monospacedDigit()
                }
                .foregroundColor(Color(red: 1.0, green: 0.86, blue: 0.42))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.16, blue: 0.23),
                    Color(red: 0.15, green: 0.25, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                timerCircle(diameter: 140)
                restControls(maxWidth: 220)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                timerCircle(diameter: 168)
                restControls(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func timerCircle(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 10)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            VStack(spacing: 2) {
                Text("Rest")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Text(formattedTime)
                    .font(.system(size: diameter * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private func restControls(maxWidth: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                RestAdjustButton(label: "-10s") { onAddTime(-10) }
                RestAdjustButton(label: "+10s") { onAddTime(10) }
                RestAdjustButton(label: "+30s") { onAddTime(30) }
            }
            .frame(maxWidth: .infinity)

            Button(action: onDismiss) {
                Label("Skip Rest", systemImage: "forward.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: maxWidth)
    }
}

private struct RestAdjustButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundColor(.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct WorkoutPlanPreviewCard: View {
    let exercises: [WorkoutDayPlanExerciseDetail]
    let canShuffle: Bool
    let message: String?
    let onShuffle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Plan")
                        .font(.headline)
                    Text("You can reshuffle this generated plan until the first set is logged.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onShuffle) {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canShuffle)
                .opacity(canShuffle ? 1 : 0.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(exercises) { detail in
                        VStack(alignment: .leading, spacing: 6) {
                            if detail.planExercise.isAnchor {
                                Text("Anchor")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.16), in: Capsule())
                            }

                            Text(detail.exercise.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                if let sets = detail.planExercise.targetSets {
                                    Label("\(sets)", systemImage: "square.stack.3d.up")
                                }
                                if let reps = detail.planExercise.targetReps {
                                    Label("\(reps)", systemImage: "repeat")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(width: 170, alignment: .leading)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct WarmupCardioPrompt: View {
    @Binding var selectedType: CardioType
    let onAddWarmup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("10 Min Warm-up", systemImage: "figure.run")
                    .font(.headline)
                Spacer()
            }

            Text("Starte jedes Workout mit Cardio auf dem Gerät deiner Wahl.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Cardio Type", selection: $selectedType) {
                ForEach(CardioType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            Button(action: onAddWarmup) {
                Label("Warm-up hinzufügen", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct FinisherCardioPrompt: View {
    let onAddCardio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional: Cardio Finisher")
                .font(.headline)
            Text("Wenn du noch Energie hast, hänge zum Schluss Cardio dran.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: onAddCardio) {
                Label("Cardio hinzufügen", systemImage: "figure.run")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CurrentExerciseView: View {
    let detail: TemplateExerciseDetail
    let completedSets: [SessionSet]
    let lastEnteredValues: (reps: Int?, weight: Double?)
    let isLoggingEnabled: Bool
    let loggingHint: String?
    let onLogSet: (Int?, Int?, Double?) -> Void
    let onDeleteSet: (SessionSet) -> Void

    @State private var repsInput: String = ""
    @State private var durationInput: String = ""
    @State private var weightInput: String = ""
    @State private var hasInitialized: Bool = false

    var exercise: Exercise { detail.exercise }
    var templateExercise: TemplateExercise { detail.templateExercise }

    private var equipmentIsBarbell: Bool {
        let eq = (exercise.equipment ?? "").lowercased()
        // Check for various barbell terms in multiple languages
        let barbellTerms = [
            "barbell", "langhantel", "sz",  // German & English common terms
            "bar", "stange",                 // Short forms
            "ez bar", "curl bar",            // Specific barbell types
            "olympia", "olympic",            // Olympic barbells
            "straight bar", "gerade"         // Straight bar variations
        ]
        return barbellTerms.contains { eq.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(exercise.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !exercise.muscleGroups.isEmpty {
                        Text(exercise.muscleGroups.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let notes = exercise.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    HStack(spacing: 10) {
                        if let sets = templateExercise.targetSets {
                            TargetBadge(label: "Sets", value: "\(sets)")
                        }
                        if exercise.exerciseType == .reps, let reps = templateExercise.targetReps {
                            TargetBadge(label: "Reps", value: "\(reps)")
                        }
                        if exercise.exerciseType == .timed, let duration = templateExercise.targetDuration {
                            TargetBadge(label: "Duration", value: formatDuration(duration))
                        }
                        if let weight = templateExercise.targetWeight {
                            TargetBadge(label: "Weight", value: "\(Int(weight)) kg")
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Text("Set \(completedSets.count + 1)")
                            .font(.headline)

                        if let targetSets = templateExercise.targetSets {
                            if completedSets.count + 1 > targetSets {
                                Text("(+\(completedSets.count + 1 - targetSets))")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .fontWeight(.semibold)
                            } else {
                                Text("of \(targetSets)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }

                    if exercise.exerciseType == .reps {
                        HStack(spacing: 10) {
                            WorkoutInputField(
                                title: "Reps",
                                text: $repsInput,
                                keyboardType: .numberPad
                            )
                            WorkoutInputField(
                                title: equipmentIsBarbell ? "Gesamt kg" : "Weight (kg)",
                                text: $weightInput,
                                keyboardType: .decimalPad
                            )
                        }

                        if equipmentIsBarbell {
                            VStack(spacing: 3) {
                                Text("Gesamtgewicht der Langhantel (Stange + Scheiben)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                if let weight = parseDecimal(weightInput), weight >= 20 {
                                    let perSide = (weight - 20) / 2
                                    Text("= 20 kg Stange + \(String(format: "%.1f", perSide)) kg pro Seite")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            WorkoutInputField(
                                title: "Duration (sec)",
                                text: $durationInput,
                                keyboardType: .numberPad
                            )
                            WorkoutInputField(
                                title: "Weight (kg)",
                                text: $weightInput,
                                keyboardType: .decimalPad
                            )
                        }
                    }

                    Button {
                        logCurrentSet()
                    } label: {
                        Label("Log Set", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!isLoggingEnabled)
                    .opacity(isLoggingEnabled ? 1 : 0.5)

                    if let hint = loggingHint, !hint.isEmpty {
                        Text(hint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if !completedSets.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Completed Sets")
                            .font(.headline)

                        ForEach(completedSets) { set in
                            CompletedSetRow(set: set, exerciseType: exercise.exerciseType)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        onDeleteSet(set)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            initializeInputs()
        }
        .onChange(of: detail.exercise.id) { _, _ in
            // Re-initialize when exercise changes
            hasInitialized = false
            initializeInputs()
        }
    }

    private func initializeInputs() {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Use last entered values if available, otherwise fall back to template defaults
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
        let reps = exercise.exerciseType == .reps ? Int(repsInput) : nil
        let duration = exercise.exerciseType == .timed ? Int(durationInput) : nil
        let weight = parseDecimal(weightInput)

        onLogSet(reps, duration, weight)

        // Keep the entered values for the next set (don't reset to template defaults)
        // The values stay as they are - user can modify if needed
    }
}

struct TargetBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct WorkoutInputField: View {
    let title: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            TextField("0", text: $text)
                .keyboardType(keyboardType)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CompletedSetRow: View {
    let set: SessionSet
    let exerciseType: ExerciseType

    var body: some View {
        HStack {
            Text("Set \(set.setNumber)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if exerciseType == .reps {
                if let reps = set.reps {
                    Text("\(reps) reps")
                }
            } else {
                if let duration = set.duration {
                    Text(formatDuration(duration))
                }
            }

            if set.weight != nil {
                Text("@ \(set.formattedWeight)")
            }

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct EmptyWorkoutView: View {
    let onAddExercise: () -> Void
    let onAddCardio: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dumbbell")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Add exercises to your workout")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: onAddExercise) {
                    Label("Add Exercise", systemImage: "plus")
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: onAddCardio) {
                    Label("Add Cardio", systemImage: "figure.run")
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
    }
}

struct WorkoutCompletedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("All exercises completed!")
                .font(.title2)
                .fontWeight(.bold)

            Text("Tap Finish to save your workout")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct WorkoutNavigationBar: View {
    let currentIndex: Int
    let totalExercises: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    let isFirstExercise: Bool
    let isLastExercise: Bool

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(Color(.systemBackground), in: Circle())
            }
            .disabled(isFirstExercise)
            .opacity(isFirstExercise ? 0.3 : 1)

            Spacer()

            if totalExercises > 0 {
                Text("\(currentIndex + 1) / \(totalExercises)")
                    .font(.headline)
            }

            Spacer()

            if isLastExercise {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground), in: Capsule())
                }
            } else {
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground), in: Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}
