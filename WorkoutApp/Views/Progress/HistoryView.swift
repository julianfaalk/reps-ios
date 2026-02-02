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
    @State private var showingExerciseDetails = false

    var body: some View {
        NavigationStack {
            Group {
                if let session = session {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header with date
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.green)

                                if let templateName = session.template?.name {
                                    Text(templateName)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }

                                Text(session.session.startedAt, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top)

                            // Stats grid (same as SessionSummaryView)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                HistoryStatCard(title: "Duration", value: session.session.formattedDuration, icon: "timer")
                                HistoryStatCard(title: "Exercises", value: "\(session.exercisesCompleted)", icon: "figure.strengthtraining.traditional")
                                HistoryStatCard(title: "Total Sets", value: "\(session.totalSets)", icon: "square.stack.3d.up")
                                HistoryStatCard(title: "Total Reps", value: "\(session.totalReps)", icon: "repeat")
                            }
                            .padding(.horizontal)

                            // Volume
                            if session.totalVolume > 0 {
                                HStack {
                                    Image(systemName: "scalemass")
                                        .foregroundColor(.accentColor)
                                    Text("Total Volume")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.0f kg", session.totalVolume))
                                        .font(.headline)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }

                            // Cardio sessions
                            if !session.cardioSessions.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Cardio")
                                        .font(.headline)
                                        .padding(.horizontal)

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
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                    }
                                }
                            }

                            // Exercise details (collapsible)
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    withAnimation {
                                        showingExerciseDetails.toggle()
                                    }
                                } label: {
                                    HStack {
                                        Text("Exercise Details")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: showingExerciseDetails ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal)
                                }

                                if showingExerciseDetails {
                                    let groupedSets = Dictionary(grouping: session.sets, by: { $0.exercise.id })
                                    ForEach(Array(groupedSets.keys), id: \.self) { exerciseId in
                                        if let sets = groupedSets[exerciseId], let first = sets.first {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(first.exercise.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)

                                                ForEach(sets) { setWithExercise in
                                                    HStack {
                                                        Text("Set \(setWithExercise.sessionSet.setNumber)")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                            .frame(width: 50, alignment: .leading)

                                                        Spacer()

                                                        if first.exercise.exerciseType == .reps {
                                                            if let reps = setWithExercise.sessionSet.reps {
                                                                Text("\(reps) reps")
                                                                    .font(.subheadline)
                                                            }
                                                        } else {
                                                            if let duration = setWithExercise.sessionSet.duration {
                                                                Text(formatDuration(duration))
                                                                    .font(.subheadline)
                                                            }
                                                        }

                                                        if setWithExercise.sessionSet.weight != nil {
                                                            Text("@ \(setWithExercise.sessionSet.formattedWeight)")
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                }
                                            }
                                            .padding()
                                            .background(Color(.systemGray6))
                                            .cornerRadius(8)
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                            }

                            // Notes section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(.headline)
                                    .padding(.horizontal)

                                if editingNotes {
                                    TextEditor(text: $notes)
                                        .frame(minHeight: 80)
                                        .padding(8)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                        .padding(.horizontal)

                                    Button("Save Notes") {
                                        saveNotes()
                                    }
                                    .padding(.horizontal)
                                } else {
                                    VStack(alignment: .leading) {
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
                                        .font(.subheadline)
                                        .padding(.top, 4)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                            }

                            // Delete button
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Workout")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Workout Summary")
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

struct HistoryStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    HistoryView()
}
