import SwiftUI

struct TemplateFormView: View {
    @ObservedObject var viewModel: TemplateViewModel
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate?

    @State private var name: String = ""
    @State private var isSaving = false

    init(viewModel: TemplateViewModel, template: WorkoutTemplate? = nil) {
        self.viewModel = viewModel
        self.template = template
    }

    var isEditing: Bool {
        template != nil
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template Name", text: $name)
                }

                Section {
                    Text("You can add exercises after creating the template.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                if let template = template {
                    name = template.name
                }
            }
        }
    }

    private func saveTemplate() {
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var newTemplate = template ?? WorkoutTemplate(name: trimmedName)
        newTemplate.name = trimmedName

        Task {
            if await viewModel.saveTemplate(newTemplate) {
                dismiss()
            }
            isSaving = false
        }
    }
}
