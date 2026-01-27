import SwiftUI

struct ExerciseListView: View {
    @StateObject private var viewModel = ExerciseViewModel()
    @State private var showingAddExercise = false
    @State private var selectedExercise: Exercise?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $viewModel.searchText, placeholder: "Search exercises...")
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Muscle group filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            title: "All",
                            isSelected: viewModel.selectedMuscleGroup == nil
                        ) {
                            viewModel.selectedMuscleGroup = nil
                        }

                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            FilterChip(
                                title: muscle.rawValue,
                                isSelected: viewModel.selectedMuscleGroup == muscle.rawValue
                            ) {
                                viewModel.selectedMuscleGroup = muscle.rawValue
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Exercise list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.filteredExercises.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Exercises",
                        systemImage: "dumbbell",
                        description: Text("Add your first exercise to get started")
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.filteredExercises) { exercise in
                            ExerciseRowView(exercise: exercise)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedExercise = exercise
                                }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let exercise = viewModel.filteredExercises[index]
                                    await viewModel.deleteExercise(exercise)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExerciseFormView(viewModel: viewModel)
            }
            .sheet(item: $selectedExercise) { exercise in
                ExerciseDetailView(exercise: exercise, viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadExercises()
            }
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise.name)
                    .font(.headline)

                Spacer()

                Text(exercise.exerciseType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(exercise.exerciseType == .reps ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(exercise.exerciseType == .reps ? .blue : .orange)
                    .cornerRadius(8)
            }

            if !exercise.muscleGroups.isEmpty {
                Text(exercise.muscleGroups.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let equipment = exercise.equipment, !equipment.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "dumbbell")
                        .font(.caption)
                    Text(equipment)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

#Preview {
    ExerciseListView()
}
