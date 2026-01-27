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
                        formattedTime: viewModel.formattedRestTime,
                        onDismiss: { viewModel.stopRestTimer() },
                        onAddTime: { viewModel.addRestTime(30) }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Main content
                if let currentExercise = viewModel.currentExercise {
                    CurrentExerciseView(
                        detail: currentExercise,
                        completedSets: viewModel.completedSetsForCurrentExercise,
                        onLogSet: { reps, duration, weight in
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
                AddCardioView { cardio in
                    Task {
                        await viewModel.addCardioSession(cardio)
                    }
                }
            }
            .sheet(isPresented: $showingSessionSummary) {
                if let session = completedSession {
                    SessionSummaryView(session: session, newPRs: viewModel.newPRs) {
                        dismiss()
                    }
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
    let formattedTime: String
    let onDismiss: () -> Void
    let onAddTime: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Rest")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(formattedTime)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 20) {
                Button(action: onAddTime) {
                    Label("+30s", systemImage: "plus")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }

                Button(action: onDismiss) {
                    Label("Skip", systemImage: "forward.fill")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
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
    let onLogSet: (Int?, Int?, Double?) -> Void
    let onDeleteSet: (SessionSet) -> Void

    @State private var repsInput: String = ""
    @State private var durationInput: String = ""
    @State private var weightInput: String = ""

    var exercise: Exercise { detail.exercise }
    var templateExercise: TemplateExercise { detail.templateExercise }

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
                    Text("Set \(completedSets.count + 1)")
                        .font(.headline)

                    if exercise.exerciseType == .reps {
                        HStack(spacing: 16) {
                            VStack {
                                Text("Reps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("0", text: $repsInput)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.center)
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
        .onAppear {
            // Pre-fill with target values
            if let reps = templateExercise.targetReps {
                repsInput = "\(reps)"
            }
            if let duration = templateExercise.targetDuration {
                durationInput = "\(duration)"
            }
            if let weight = templateExercise.targetWeight {
                weightInput = weight.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(weight))"
                    : String(format: "%.1f", weight)
            }
        }
    }

    private func logCurrentSet() {
        let reps = exercise.exerciseType == .reps ? Int(repsInput) : nil
        let duration = exercise.exerciseType == .timed ? Int(durationInput) : nil
        let weight = Double(weightInput)

        onLogSet(reps, duration, weight)

        // Keep weight, clear reps/duration for next set
        repsInput = templateExercise.targetReps.map { "\($0)" } ?? ""
        durationInput = templateExercise.targetDuration.map { "\($0)" } ?? ""
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
