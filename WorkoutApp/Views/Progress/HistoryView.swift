import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var selectedSession: SessionWithDetails?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            Button {
                                selectedSession = session
                            } label: {
                                HistorySessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    let session = viewModel.filteredSessions[index]
                                    _ = await viewModel.deleteSession(session.session)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Workout History")
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.template?.name ?? "Ad-hoc Workout")
                        .font(.headline)

                    Text(session.session.startedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.session.formattedDuration)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Open")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            HStack(spacing: 14) {
                Label("\(session.exercisesCompleted)", systemImage: "figure.strengthtraining.traditional")
                Label("\(session.totalSets)", systemImage: "square.stack.3d.up")
                Label("\(session.totalReps)", systemImage: "repeat")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
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
    @State private var expandedExercises = true
    @State private var setToEdit: EditableSessionSet?
    @State private var setToDelete: EditableSessionSet?

    private var exerciseGroups: [ExerciseSetGroup] {
        guard let session else { return [] }

        return Dictionary(grouping: session.sets, by: { $0.exercise.id })
            .compactMap { _, grouped in
                guard let first = grouped.first else { return nil }
                let sortedSets = grouped.sorted { $0.sessionSet.setNumber < $1.sessionSet.setNumber }
                return ExerciseSetGroup(exercise: first.exercise, sets: sortedSets)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.sets.first?.sessionSet.completedAt ?? .distantPast
                let rhsDate = rhs.sets.first?.sessionSet.completedAt ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerCard(session)
                            statsSection(session)

                            if session.totalVolume > 0 {
                                volumeCard(session)
                            }

                            notesSection(session)

                            exercisesSection

                            if !session.cardioSessions.isEmpty {
                                cardioSection(session)
                            }

                            deleteWorkoutButton
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Workout Details")
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
                    await reloadSession()
                }
            }
            .sheet(item: $setToEdit) { editableSet in
                EditSessionSetSheet(editableSet: editableSet) { updatedSet in
                    Task {
                        if await viewModel.updateSet(updatedSet) {
                            await reloadSession()
                        }
                    }
                }
            }
            .alert("Delete Workout?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let session {
                        Task {
                            if await viewModel.deleteSession(session.session) {
                                dismiss()
                            }
                        }
                    }
                }
            } message: {
                Text("This will permanently delete this workout session.")
            }
            .alert("Delete Set?", isPresented: Binding(
                get: { setToDelete != nil },
                set: { if !$0 { setToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    setToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    guard let setToDelete else { return }
                    Task {
                        if await viewModel.deleteSet(setToDelete.sessionSet) {
                            await reloadSession()
                        }
                        self.setToDelete = nil
                    }
                }
            } message: {
                Text("This removes the set from the workout history.")
            }
        }
    }

    @ViewBuilder
    private func headerCard(_ session: SessionWithDetails) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.accentColor)
                Text(session.template?.name ?? "Ad-hoc Workout")
                    .font(.headline)
                Spacer()
            }

            HStack {
                Text(session.session.startedAt, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func statsSection(_ session: SessionWithDetails) -> some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

        LazyVGrid(columns: columns, spacing: 12) {
            HistoryStatCard(title: "Duration", value: session.session.formattedDuration, icon: "timer")
            HistoryStatCard(title: "Exercises", value: "\(session.exercisesCompleted)", icon: "figure.strengthtraining.traditional")
            HistoryStatCard(title: "Sets", value: "\(session.totalSets)", icon: "square.stack.3d.up")
            HistoryStatCard(title: "Reps", value: "\(session.totalReps)", icon: "repeat")
        }
    }

    @ViewBuilder
    private func volumeCard(_ session: SessionWithDetails) -> some View {
        HStack {
            Label("Total Volume", systemImage: "scalemass")
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.0f kg", session.totalVolume))
                .font(.headline)
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func notesSection(_ session: SessionWithDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Button(editingNotes ? "Cancel" : "Edit") {
                    if editingNotes {
                        editingNotes = false
                        notes = session.session.notes ?? ""
                    } else {
                        notes = session.session.notes ?? ""
                        editingNotes = true
                    }
                }
                .font(.subheadline)
            }

            if editingNotes {
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    saveNotes()
                } label: {
                    Text("Save Notes")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                if let existingNotes = session.session.notes, !existingNotes.isEmpty {
                    Text(existingNotes)
                } else {
                    Text("No notes yet")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedExercises.toggle()
                }
            } label: {
                HStack {
                    Text("Exercises")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expandedExercises ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expandedExercises {
                ForEach(exerciseGroups) { group in
                    ExerciseHistoryCard(
                        group: group,
                        onEditSet: { set in
                            setToEdit = EditableSessionSet(exercise: group.exercise, sessionSet: set)
                        },
                        onDeleteSet: { set in
                            setToDelete = EditableSessionSet(exercise: group.exercise, sessionSet: set)
                        }
                    )
                }
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func cardioSection(_ session: SessionWithDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cardio")
                .font(.headline)

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
                .padding(10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var deleteWorkoutButton: some View {
        Button(role: .destructive) {
            showingDeleteAlert = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Workout")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func saveNotes() {
        guard var sessionModel = session?.session else { return }
        sessionModel.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes

        Task {
            if await viewModel.updateSession(sessionModel) {
                await reloadSession()
                editingNotes = false
            }
        }
    }

    private func reloadSession() async {
        session = await viewModel.getSessionDetails(id: sessionId)
    }
}

struct ExerciseHistoryCard: View {
    let group: ExerciseSetGroup
    let onEditSet: (SessionSet) -> Void
    let onDeleteSet: (SessionSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.exercise.name)
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(group.sets) { setWithExercise in
                HStack(spacing: 8) {
                    Text("Set \(setWithExercise.sessionSet.setNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)

                    Spacer()

                    if group.exercise.exerciseType == .reps {
                        Text("\(setWithExercise.sessionSet.reps ?? 0) reps")
                            .font(.subheadline)
                    } else {
                        Text(setWithExercise.sessionSet.duration.map(formatDuration) ?? "0:00")
                            .font(.subheadline)
                    }

                    if setWithExercise.sessionSet.weight != nil {
                        Text("@ \(setWithExercise.sessionSet.formattedWeight)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        onEditSet(setWithExercise.sessionSet)
                    } label: {
                        Image(systemName: "pencil.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Button {
                        onDeleteSet(setWithExercise.sessionSet)
                    } label: {
                        Image(systemName: "trash.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                .padding(10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct EditSessionSetSheet: View {
    let editableSet: EditableSessionSet
    let onSave: (SessionSet) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var repsInput: String = ""
    @State private var durationInput: String = ""
    @State private var weightInput: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    if editableSet.exercise.exerciseType == .reps {
                        TextField("Reps", text: $repsInput)
                            .keyboardType(.numberPad)
                    } else {
                        TextField("Duration (sec)", text: $durationInput)
                            .keyboardType(.numberPad)
                    }

                    TextField("Weight (kg)", text: $weightInput)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = editableSet.sessionSet
                        updated.reps = editableSet.exercise.exerciseType == .reps ? Int(repsInput) : nil
                        updated.duration = editableSet.exercise.exerciseType == .timed ? Int(durationInput) : nil
                        updated.weight = weightInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parseDecimal(weightInput)
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                repsInput = editableSet.sessionSet.reps.map(String.init) ?? ""
                durationInput = editableSet.sessionSet.duration.map(String.init) ?? ""
                if let weight = editableSet.sessionSet.weight {
                    weightInput = weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
                } else {
                    weightInput = ""
                }
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
                .font(.title3)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ExerciseSetGroup: Identifiable {
    let exercise: Exercise
    let sets: [SessionSetWithExercise]

    var id: UUID { exercise.id }
}

struct EditableSessionSet: Identifiable {
    let exercise: Exercise
    let sessionSet: SessionSet

    var id: UUID { sessionSet.id }
}

#Preview {
    HistoryView()
}
