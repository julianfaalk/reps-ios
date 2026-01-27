import SwiftUI

struct AddExerciseToTemplateView: View {
    let templateId: UUID
    @ObservedObject var viewModel: TemplateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExercise: Exercise?
    @State private var targetSets: String = "3"
    @State private var targetReps: String = "10"
    @State private var targetDuration: String = "30"
    @State private var targetWeight: String = ""
    @State private var showingExercisePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    if let exercise = selectedExercise {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.name)
                                    .font(.headline)
                                Text(exercise.exerciseType.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Change") {
                                showingExercisePicker = true
                            }
                        }
                    } else {
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Select Exercise", systemImage: "plus.circle")
                        }
                    }
                }

                if let exercise = selectedExercise {
                    Section("Targets (Optional)") {
                        HStack {
                            Text("Sets")
                            Spacer()
                            TextField("Sets", text: $targetSets)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }

                        if exercise.exerciseType == .reps {
                            HStack {
                                Text("Reps")
                                Spacer()
                                TextField("Reps", text: $targetReps)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                            }
                        } else {
                            HStack {
                                Text("Duration (seconds)")
                                Spacer()
                                TextField("Duration", text: $targetDuration)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                            }
                        }

                        HStack {
                            Text("Weight (kg)")
                            Spacer()
                            TextField("Weight", text: $targetWeight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addExercise()
                    }
                    .disabled(selectedExercise == nil)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { exercise in
                    selectedExercise = exercise
                }
            }
        }
    }

    private func addExercise() {
        guard let exercise = selectedExercise else { return }

        let sets = Int(targetSets)
        let reps = exercise.exerciseType == .reps ? Int(targetReps) : nil
        let duration = exercise.exerciseType == .timed ? Int(targetDuration) : nil
        let weight = Double(targetWeight)

        Task {
            if await viewModel.addExerciseToTemplate(
                templateId: templateId,
                exerciseId: exercise.id,
                targetSets: sets,
                targetReps: reps,
                targetDuration: duration,
                targetWeight: weight
            ) {
                dismiss()
            }
        }
    }
}
