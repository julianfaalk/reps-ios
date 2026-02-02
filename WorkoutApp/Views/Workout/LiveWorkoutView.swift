import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddExercise = false
    @State private var showingAddCardio = false
    @State private var showingFinishConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var showingSessionSummary = false
    @State private var completedSession: SessionWithDetails?

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
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Main content
                if let currentExercise = viewModel.currentExercise {
                    CurrentExerciseView(
                        detail: currentExercise,
                        completedSets: viewModel.completedSetsForCurrentExercise,
                        lastEnteredValues: viewModel.getLastEnteredValues(for: currentExercise.exercise.id),
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
                } else if viewModel.templateExercises.isEmpty {
                    EmptyWorkoutView(
                        onAddExercise: { showingAddExercise = true },
                        onAddCardio: { showingAddCardio = true }
                    )
                } else {
                    WorkoutCompletedView()
                }

                Spacer()

                // Bottom navigation
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

            Spacer()

            if isRestTimerActive {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                    Text(restTimeRemaining)
                        .font(.headline)
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
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
        VStack(spacing: 20) {
            Text("Rest")
                .font(.headline)
                .foregroundColor(.secondary)

            // Circular progress timer
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 12)
                    .frame(width: 180, height: 180)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)

                // Time display
                Text(formattedTime)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            // +/- buttons row
            HStack(spacing: 12) {
                Button {
                    onAddTime(-10)
                } label: {
                    Text("-10s")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }

                Button {
                    onAddTime(10)
                } label: {
                    Text("+10s")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }

                Button {
                    onAddTime(30)
                } label: {
                    Text("+30s")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }
            }

            Button(action: onDismiss) {
                Label("Skip Rest", systemImage: "forward.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}

struct CurrentExerciseView: View {
    let detail: TemplateExerciseDetail
    let completedSets: [SessionSet]
    let lastEnteredValues: (reps: Int?, weight: Double?)
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
            VStack(spacing: 20) {
                // Exercise header
                VStack(spacing: 8) {
                    Text(exercise.name)
                        .font(.title)
                        .fontWeight(.bold)

                    if !exercise.muscleGroups.isEmpty {
                        Text(exercise.muscleGroups.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let notes = exercise.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // Target info
                    HStack(spacing: 16) {
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
                .padding()

                // Input section
                VStack(spacing: 16) {
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
                    }

                    if exercise.exerciseType == .reps {
                        HStack(spacing: 16) {
                            VStack {
                                Text("Reps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("0", text: $repsInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("Done") {
                                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            }
                                        }
                                    }
                                    .frame(width: 80)
                                    .multilineTextAlignment(.center)
                            }

                            VStack {
                                Text(equipmentIsBarbell ? "Gesamt kg" : "Weight (kg)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("0", text: $weightInput)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("Done") {
                                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            }
                                        }
                                    }
                                    .frame(width: 100)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        if equipmentIsBarbell {
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
                    } else {
                        HStack(spacing: 16) {
                            VStack {
                                Text("Duration (sec)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("0", text: $durationInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
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

                            VStack {
                                Text("Weight (kg)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("0", text: $weightInput)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
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
                        }
                    }

                    Button {
                        logCurrentSet()
                    } label: {
                        Label("Log Set", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)

                // Completed sets
                if !completedSets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
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
                    .padding()
                }
            }
            .padding()
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

            if let weight = set.weight {
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
                    .font(.title2)
                    .padding()
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
                        .padding()
                }
            } else {
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .padding()
                }
            }
        }
        .padding(.horizontal)
        .background(Color(.systemGray6))
    }
}
