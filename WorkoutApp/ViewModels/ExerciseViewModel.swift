import Foundation
import SwiftUI

@MainActor
class ExerciseViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var filteredExercises: [Exercise] = []
    @Published var searchText: String = "" {
        didSet { filterExercises() }
    }
    @Published var selectedMuscleGroup: String? = nil {
        didSet { filterExercises() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = DatabaseService.shared

    init() {
        Task {
            await loadExercises()
        }
    }

    func loadExercises() async {
        isLoading = true
        do {
            exercises = try db.fetchAllExercises()
            filterExercises()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func filterExercises() {
        var result = exercises

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if let muscleGroup = selectedMuscleGroup {
            result = result.filter { $0.muscleGroups.contains(muscleGroup) }
        }

        filteredExercises = result
    }

    func saveExercise(_ exercise: Exercise) async -> Bool {
        do {
            try db.saveExercise(exercise)
            await loadExercises()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteExercise(_ exercise: Exercise) async -> Bool {
        do {
            try db.deleteExercise(exercise)
            await loadExercises()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func getExercise(id: UUID) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func getCurrentPR(exerciseId: UUID) -> PersonalRecord? {
        try? db.fetchCurrentPR(exerciseId: exerciseId)
    }
}
