import SwiftUI

struct TemplateDetailView: View {
    let templateId: UUID
    @ObservedObject var viewModel: TemplateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddExercise = false
    @State private var showingEditTemplate = false
    @State private var showingDeleteAlert = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading template...")
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Error Loading Template",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let templateWithExercises = viewModel.currentTemplate {
                List {
                    Section("Exercises") {
                        if templateWithExercises.exercises.isEmpty {
                            Text("No exercises added yet")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(templateWithExercises.exercises) { detail in
                                TemplateExerciseRow(detail: detail)
                            }
                            .onDelete { indexSet in
                                Task {
                                    for index in indexSet {
                                        let exercise = templateWithExercises.exercises[index]
                                        await viewModel.removeExerciseFromTemplate(exercise.templateExercise)
                                    }
                                }
                            }
                            .onMove { source, destination in
                                Task {
                                    await viewModel.reorderExercises(
                                        templateId: templateId,
                                        from: source,
                                        to: destination
                                    )
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            showingAddExercise = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus")
                        }
                    }

                    Section {
                        Button("Edit Template Name") {
                            showingEditTemplate = true
                        }

                        Button("Delete Template", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    }
                }
                .navigationTitle(templateWithExercises.name)
                .toolbar {
                    EditButton()
                }
            } else {
                ContentUnavailableView(
                    "Template Not Found",
                    systemImage: "doc.text.slash",
                    description: Text("This template could not be loaded")
                )
            }
        }
        .onAppear {
            Task {
                await viewModel.loadTemplate(id: templateId)
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToTemplateView(templateId: templateId, viewModel: viewModel)
        }
        .sheet(isPresented: $showingEditTemplate) {
            if let template = viewModel.currentTemplate?.template {
                TemplateFormView(viewModel: viewModel, template: template)
            }
        }
        .alert("Delete Template?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let template = viewModel.currentTemplate?.template {
                    Task {
                        if await viewModel.deleteTemplate(template) {
                            dismiss()
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently delete this template.")
        }
    }
}

struct TemplateExerciseRow: View {
    let detail: TemplateExerciseDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.exercise.name)
                .font(.headline)

            HStack(spacing: 12) {
                if let sets = detail.templateExercise.targetSets {
                    Label("\(sets) sets", systemImage: "square.stack.3d.up")
                }

                if detail.exercise.exerciseType == .reps {
                    if let reps = detail.templateExercise.targetReps {
                        Label("\(reps) reps", systemImage: "repeat")
                    }
                } else {
                    if let duration = detail.templateExercise.targetDuration {
                        Label(formatDuration(duration), systemImage: "timer")
                    }
                }

                if let weight = detail.templateExercise.targetWeight {
                    Label("\(Int(weight)) kg", systemImage: "scalemass")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
