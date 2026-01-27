import SwiftUI

struct ScheduleView: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @State private var selectedDay: ScheduleDay?
    @State private var showingTemplates = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Week overview
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.getOrderedDays()) { day in
                            ScheduleDayCard(day: day) {
                                selectedDay = day
                            }
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
            .sheet(item: $selectedDay) { day in
                AssignTemplateView(day: day, viewModel: viewModel)
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

    var isToday: Bool {
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        return day.dayOfWeek == today
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

// Make ScheduleDay identifiable for sheet
extension ScheduleDay: Identifiable { }

#Preview {
    ScheduleView()
}
