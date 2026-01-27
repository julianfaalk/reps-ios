import SwiftUI

struct AddCardioView: View {
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID
    let onSave: (CardioSession) -> Void

    @State private var cardioType: CardioType = .treadmill
    @State private var durationMinutes: String = "30"
    @State private var distance: String = ""
    @State private var calories: String = ""
    @State private var avgHeartRate: String = ""
    @State private var maxHeartRate: String = ""
    @State private var incline: String = ""
    @State private var resistance: String = ""
    @State private var notes: String = ""

    init(sessionId: UUID = UUID(), onSave: @escaping (CardioSession) -> Void) {
        self.sessionId = sessionId
        self.onSave = onSave
    }

    var isValid: Bool {
        guard let minutes = Int(durationMinutes), minutes > 0 else {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Cardio Type", selection: $cardioType) {
                        ForEach(CardioType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Duration") {
                    HStack {
                        TextField("Minutes", text: $durationMinutes)
                            .keyboardType(.numberPad)
                        Text("minutes")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Metrics (Optional)") {
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("km", text: $distance)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("km")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("kcal", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Heart Rate (Optional)") {
                    HStack {
                        Text("Average")
                        Spacer()
                        TextField("bpm", text: $avgHeartRate)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("bpm")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("bpm", text: $maxHeartRate)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("bpm")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Other (Optional)") {
                    HStack {
                        Text("Incline")
                        Spacer()
                        TextField("%", text: $incline)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Resistance")
                        Spacer()
                        TextField("Level", text: $resistance)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCardio()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveCardio() {
        guard let minutes = Int(durationMinutes) else { return }

        let cardio = CardioSession(
            sessionId: sessionId,
            cardioType: cardioType,
            duration: minutes * 60,
            distance: Double(distance),
            calories: Int(calories),
            avgHeartRate: Int(avgHeartRate),
            maxHeartRate: Int(maxHeartRate),
            incline: Double(incline),
            resistance: Int(resistance),
            notes: notes.isEmpty ? nil : notes
        )

        onSave(cardio)
        dismiss()
    }
}

#Preview {
    AddCardioView { _ in }
}
