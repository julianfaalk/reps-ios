import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var selectedSession: SessionWithDetails?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and filters
                VStack(spacing: 8) {
                    SearchBar(text: $viewModel.searchText, placeholder: "Search exercises...")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HistoryViewModel.DateRange.allCases, id: \.self) { range in
                                FilterChip(
                                    title: range.rawValue,
                                    isSelected: viewModel.selectedDateRange == range
                                ) {
                                    viewModel.selectedDateRange = range
                                }
                            }
                        }
                    }
                }
                .padding()

                // Session list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.filteredSessions.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Workouts Found",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Complete a workout to see it here")
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.filteredSessions) { session in
                            HistorySessionRow(session: session)
                                .onTapGesture {
                                    selectedSession = session
                                }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let session = viewModel.filteredSessions[index]
                                    await viewModel.deleteSession(session.session)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedSession) { session in
                HistoryDetailView(sessionId: session.session.id, viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadSessions()
            }
        }
    }
}

struct HistorySessionRow: View {
    let session: SessionWithDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.template?.name ?? "Ad-hoc Workout")
                    .font(.headline)

                Spacer()

                Text(session.session.formattedDuration)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text(session.session.startedAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label("\(session.exercisesCompleted) exercises", systemImage: "figure.strengthtraining.traditional")
                Label("\(session.totalSets) sets", systemImage: "square.stack.3d.up")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct HistoryDetailView: View {
    let sessionId: UUID
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var session: SessionWithDetails?
    @State private var showingDeleteAlert = false
    @State private var editingNotes = false
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if let session = session {
                    List {
                        // Summary section
                        Section("Summary") {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text(session.session.formattedDuration)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Exercises")
                                Spacer()
                                Text("\(session.exercisesCompleted)")
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Total Sets")
                                Spacer()
                                Text("\(session.totalSets)")
                                    .foregroundColor(.secondary)
                            }

                            if session.totalVolume > 0 {
                                HStack {
                                    Text("Total Volume")
                                    Spacer()
                                    Text(String(format: "%.0f kg", session.totalVolume))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Sets by exercise
                        let groupedSets = Dictionary(grouping: session.sets, by: { $0.exercise.id })
                        ForEach(Array(groupedSets.keys), id: \.self) { exerciseId in
                            if let sets = groupedSets[exerciseId], let first = sets.first {
                                Section(first.exercise.name) {
                                    ForEach(sets) { setWithExercise in
                                        HStack {
                                            Text("Set \(setWithExercise.sessionSet.setNumber)")

                                            Spacer()

                                            if first.exercise.exerciseType == .reps {
                                                if let reps = setWithExercise.sessionSet.reps {
                                                    Text("\(reps) reps")
                                                }
                                            } else {
                                                if let duration = setWithExercise.sessionSet.duration {
                                                    Text(formatDuration(duration))
                                                }
                                            }

                                            if let weight = setWithExercise.sessionSet.weight {
                                                Text("@ \(setWithExercise.sessionSet.formattedWeight)")
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Cardio
                        if !session.cardioSessions.isEmpty {
                            Section("Cardio") {
                                ForEach(session.cardioSessions) { cardio in
                                    HStack {
                                        Image(systemName: cardio.cardioType.icon)
                                        Text(cardio.cardioType.displayName)
                                        Spacer()
                                        Text(cardio.formattedDuration)
                                        if let distance = cardio.formattedDistance {
                                            Text(distance)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        Section("Notes") {
                            if editingNotes {
                                TextEditor(text: $notes)
                                    .frame(minHeight: 60)
                                Button("Save Notes") {
                                    saveNotes()
                                }
                            } else {
                                if let sessionNotes = session.session.notes, !sessionNotes.isEmpty {
                                    Text(sessionNotes)
                                } else {
                                    Text("No notes")
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                                Button("Edit Notes") {
                                    notes = session.session.notes ?? ""
                                    editingNotes = true
                                }
                            }
                        }

                        // Actions
                        Section {
                            Button("Delete Session", role: .destructive) {
                                showingDeleteAlert = true
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(session?.template?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                Task {
                    session = await viewModel.getSessionDetails(id: sessionId)
                }
            }
            .alert("Delete Session?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let s = session {
                        Task {
                            if await viewModel.deleteSession(s.session) {
                                dismiss()
                            }
                        }
                    }
                }
            } message: {
                Text("This will permanently delete this workout session.")
            }
        }
    }

    private func saveNotes() {
        guard var s = session?.session else { return }
        s.notes = notes.isEmpty ? nil : notes
        Task {
            if await viewModel.updateSession(s) {
                session = await viewModel.getSessionDetails(id: sessionId)
                editingNotes = false
            }
        }
    }
}

#Preview {
    HistoryView()
}
