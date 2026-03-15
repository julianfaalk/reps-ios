import SwiftUI

struct SessionSummaryView: View {
    @EnvironmentObject private var sessionViewModel: AppSessionViewModel
    let session: SessionWithDetails
    let newPRs: [PersonalRecord]
    let onSaveNotes: (String) -> Void
    let onDismiss: () -> Void

    @State private var notes: String = ""
    @State private var showingConfetti = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Success header
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Workout Complete!")
                            .font(.title)
                            .fontWeight(.bold)

                        if let templateName = session.template?.name {
                            Text(templateName)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatCard(title: "Duration", value: session.session.formattedDuration, icon: "timer")
                        StatCard(title: "Exercises", value: "\(session.exercisesCompleted)", icon: "figure.strengthtraining.traditional")
                        StatCard(title: "Total Sets", value: "\(session.totalSets)", icon: "square.stack.3d.up")
                        StatCard(title: "Total Reps", value: "\(session.totalReps)", icon: "repeat")
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

                    // New PRs
                    if !newPRs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(.yellow)
                                Text("New Personal Records!")
                                    .font(.headline)
                            }

                            ForEach(newPRs, id: \.id) { pr in
                                HStack {
                                    Text("PR")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.yellow)
                                        .cornerRadius(8)

                                    Text(pr.formattedWeight)
                                    Text("x \(pr.reps)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Cardio sessions
                    if !session.cardioSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
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
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)

                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    // Done button
                    Button {
                        onSaveNotes(notes)
                        Task {
                            await sessionViewModel.syncSnapshot()
                        }
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                notes = session.session.notes ?? ""
                if !newPRs.isEmpty {
                    showingConfetti = true
                }
            }
        }
    }
}

struct StatCard: View {
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
