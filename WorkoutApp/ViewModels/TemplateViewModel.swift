import Foundation
import SwiftUI

@MainActor
class TemplateViewModel: ObservableObject {
    @Published var templates: [WorkoutTemplate] = []
    @Published var currentTemplate: TemplateWithExercises?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = DatabaseService.shared

    init() {
        Task {
            await loadTemplates()
        }
    }

    func loadTemplates() async {
        isLoading = true
        do {
            templates = try db.fetchAllTemplates()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadTemplate(id: UUID) async {
        isLoading = true
        do {
            currentTemplate = try db.fetchTemplateWithExercises(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveTemplate(_ template: WorkoutTemplate) async -> Bool {
        do {
            try db.saveTemplate(template)
            await loadTemplates()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteTemplate(_ template: WorkoutTemplate) async -> Bool {
        do {
            try db.deleteTemplate(template)
            await loadTemplates()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addExerciseToTemplate(templateId: UUID, exerciseId: UUID, targetSets: Int?, targetReps: Int?, targetDuration: Int?, targetWeight: Double?) async -> Bool {
        do {
            let existingExercises = try db.fetchTemplateExercises(templateId: templateId)
            let newOrder = existingExercises.count

            let templateExercise = TemplateExercise(
                templateId: templateId,
                exerciseId: exerciseId,
                sortOrder: newOrder,
                targetSets: targetSets,
                targetReps: targetReps,
                targetDuration: targetDuration,
                targetWeight: targetWeight
            )

            try db.saveTemplateExercise(templateExercise)
            await loadTemplate(id: templateId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeExerciseFromTemplate(_ templateExercise: TemplateExercise) async -> Bool {
        do {
            try db.deleteTemplateExercise(templateExercise)
            await loadTemplate(id: templateExercise.templateId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateTemplateExercise(_ templateExercise: TemplateExercise) async -> Bool {
        do {
            try db.saveTemplateExercise(templateExercise)
            await loadTemplate(id: templateExercise.templateId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reorderExercises(templateId: UUID, from source: IndexSet, to destination: Int) async {
        guard var template = currentTemplate, template.template.id == templateId else { return }

        var exercises = template.exercises
        exercises.move(fromOffsets: source, toOffset: destination)

        // Update sort orders
        for (index, detail) in exercises.enumerated() {
            var updatedTE = detail.templateExercise
            updatedTE.sortOrder = index
            do {
                try db.saveTemplateExercise(updatedTE)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        await loadTemplate(id: templateId)
    }
}
