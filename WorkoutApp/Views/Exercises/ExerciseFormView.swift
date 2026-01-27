import SwiftUI

struct ExerciseFormView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise?

    @State private var name: String = ""
    @State private var exerciseType: ExerciseType = .reps
    @State private var selectedMuscleGroups: Set<String> = []
    @State private var equipment: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false

    init(viewModel: ExerciseViewModel, exercise: Exercise? = nil) {
        self.viewModel = viewModel
        self.exercise = exercise
    }

    var isEditing: Bool {
        exercise != nil
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise Name", text: $name)

                    Picker("Type", selection: $exerciseType) {
                        Text("Reps").tag(ExerciseType.reps)
                        Text("Timed").tag(ExerciseType.timed)
                    }
                }

                Section("Muscle Groups") {
                    ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                        Button {
                            if selectedMuscleGroups.contains(muscle.rawValue) {
                                selectedMuscleGroups.remove(muscle.rawValue)
                            } else {
                                selectedMuscleGroups.insert(muscle.rawValue)
                            }
                        } label: {
                            HStack {
                                Text(muscle.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedMuscleGroups.contains(muscle.rawValue) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Equipment (optional)", text: $equipment)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveExercise()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                if let exercise = exercise {
                    name = exercise.name
                    exerciseType = exercise.exerciseType
                    selectedMuscleGroups = Set(exercise.muscleGroups)
                    equipment = exercise.equipment ?? ""
                    notes = exercise.notes ?? ""
                }
            }
        }
    }

    private func saveExercise() {
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEquipment = equipment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var newExercise = exercise ?? Exercise(name: trimmedName)
        newExercise.name = trimmedName
        newExercise.exerciseType = exerciseType
        newExercise.muscleGroups = Array(selectedMuscleGroups).sorted()
        newExercise.equipment = trimmedEquipment.isEmpty ? nil : trimmedEquipment
        newExercise.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        Task {
            if await viewModel.saveExercise(newExercise) {
                dismiss()
            }
            isSaving = false
        }
    }
}

#Preview {
    ExerciseFormView(viewModel: ExerciseViewModel())
}
