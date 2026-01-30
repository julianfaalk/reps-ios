import SwiftUI

struct ScheduleView: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @State private var selectedDayForEdit: ScheduleDay?
    @State private var selectedDayForDetail: ScheduleDay?
    @State private var showingTemplates = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Week overview
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.getOrderedDays()) { day in
                            ScheduleDayCard(
                                day: day,
                                onTap: {
                                    if day.template != nil {
                                        selectedDayForDetail = day
                                    } else {
                                        selectedDayForEdit = day
                                    }
                                },
                                onEdit: {
                                    selectedDayForEdit = day
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingTemplates = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            .sheet(item: $selectedDayForEdit) { day in
                AssignTemplateView(day: day, viewModel: viewModel)
            }
            .sheet(item: $selectedDayForDetail) { day in
                DayDetailView(day: day, viewModel: viewModel)
            }
            .sheet(isPresented: $showingTemplates) {
                TemplateListView()
            }
            .refreshable {
                await viewModel.loadSchedule()
            }
        }
    }
}

struct ScheduleDayCard: View {
    let day: ScheduleDay
    let onTap: () -> Void
    let onEdit: () -> Void

    var isToday: Bool {
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        return day.dayOfWeek == today
    }

    var nextDate: Date {
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today) - 1 // 0 = Sunday

        var daysToAdd = day.dayOfWeek - todayWeekday
        if daysToAdd < 0 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: today) ?? today
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(day.dayName)
                            .font(.headline)

                        if isToday {
                            Text("Today")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }

                    Text(nextDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if day.isRestDay {
                        Text("Rest Day")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else if let template = day.template {
                        Text(template.name)
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    } else {
                        Text("No workout scheduled")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: day.isRestDay ? "bed.double" : (day.template != nil ? "figure.strengthtraining.traditional" : "plus.circle"))
                    .font(.title2)
                    .foregroundColor(day.isRestDay ? .orange : (day.template != nil ? .accentColor : .secondary))
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Change Template", systemImage: "pencil")
            }
        }
    }
}

struct DayDetailView: View {
    let day: ScheduleDay
    @ObservedObject var viewModel: ScheduleViewModel
    @StateObject private var templateViewModel = TemplateViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if day.isRestDay {
                    ContentUnavailableView(
                        "Rest Day",
                        systemImage: "bed.double",
                        description: Text("Take a day off to recover and rebuild")
                    )
                } else if let template = day.template {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.dayName)
                                    .font(.headline)
                                Text(template.name)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }

                        if let templateWithExercises = templateViewModel.currentTemplate {
                            Section("Exercises") {
                                if templateWithExercises.exercises.isEmpty {
                                    Text("No exercises in this template")
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(templateWithExercises.exercises) { detail in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(detail.exercise.name)
                                                .font(.headline)

                                            HStack(spacing: 12) {
                                                if let sets = detail.templateExercise.targetSets {
                                                    Label("\(sets) sets", systemImage: "square.stack.3d.up")
                                                        .font(.caption)
                                                }

                                                if detail.exercise.exerciseType == .reps {
                                                    if let reps = detail.templateExercise.targetReps {
                                                        Label("\(reps) reps", systemImage: "repeat")
                                                            .font(.caption)
                                                    }
                                                } else {
                                                    if let duration = detail.templateExercise.targetDuration {
                                                        Label(formatDuration(duration), systemImage: "timer")
                                                            .font(.caption)
                                                    }
                                                }

                                                if let weight = detail.templateExercise.targetWeight {
                                                    Label("\(Int(weight)) kg", systemImage: "scalemass")
                                                        .font(.caption)
                                                }
                                            }
                                            .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        } else {
                            Section {
                                ProgressView()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Workout Scheduled",
                        systemImage: "calendar.badge.plus",
                        description: Text("Tap to assign a template to this day")
                    )
                }
            }
            .navigationTitle(day.dayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let template = day.template {
                    Task {
                        await templateViewModel.loadTemplate(id: template.id)
                    }
                }
            }
        }
    }
}

struct AssignTemplateView: View {
    let day: ScheduleDay
    @ObservedObject var viewModel: ScheduleViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Options for \(day.dayName)") {
                    Button {
                        Task {
                            await viewModel.markAsRestDay(dayOfWeek: day.dayOfWeek)
                            dismiss()
                        }
                    } label: {
                        Label("Mark as Rest Day", systemImage: "bed.double")
                    }
                }

                Section("Assign Template") {
                    if viewModel.templates.isEmpty {
                        Text("No templates available")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(viewModel.templates) { template in
                            Button {
                                Task {
                                    await viewModel.assignTemplate(dayOfWeek: day.dayOfWeek, templateId: template.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(template.name)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if day.template?.id == template.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule")
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

#Preview {
    ScheduleView()
}
