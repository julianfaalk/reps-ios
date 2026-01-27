import SwiftUI

struct ExercisePickerView: View {
    @StateObject private var viewModel = ExerciseViewModel()
    @Environment(\.dismiss) private var dismiss

    let onSelect: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $viewModel.searchText, placeholder: "Search exercises...")
                    .padding(.horizontal)
                    .padding(.top, 8)

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

                if viewModel.filteredExercises.isEmpty {
                    ContentUnavailableView(
                        "No Exercises Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try adjusting your search or filters")
                    )
                } else {
                    List(viewModel.filteredExercises) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            ExerciseRowView(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Exercise")
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
