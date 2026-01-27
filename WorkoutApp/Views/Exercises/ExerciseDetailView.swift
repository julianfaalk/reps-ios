import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExerciseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(exercise.exerciseType.displayName)
                            .foregroundColor(.secondary)
                    }

                    if !exercise.muscleGroups.isEmpty {
                        HStack(alignment: .top) {
                            Text("Muscle Groups")
                            Spacer()
                            Text(exercise.muscleGroups.joined(separator: ", "))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if let equipment = exercise.equipment, !equipment.isEmpty {
                        HStack {
                            Text("Equipment")
                            Spacer()
                            Text(equipment)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let notes = exercise.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .foregroundColor(.secondary)
                    }
                }

                // Personal Record Section
                if let pr = viewModel.getCurrentPR(exerciseId: exercise.id) {
                    Section("Personal Record") {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(pr.formattedWeight)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("\(pr.reps) reps")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Est. 1RM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f kg", pr.estimated1RM))
                                    .font(.headline)
                            }
                        }

                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                            Text(pr.achievedAt, style: .date)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }

                Section {
                    Button("Edit Exercise") {
                        showingEditSheet = true
                    }

                    Button("Delete Exercise", role: .destructive) {
                        showingDeleteAlert = true
                    }
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                ExerciseFormView(viewModel: viewModel, exercise: exercise)
            }
            .alert("Delete Exercise?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        if await viewModel.deleteExercise(exercise) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("This will permanently delete \(exercise.name) and all associated data.")
            }
        }
    }
}
