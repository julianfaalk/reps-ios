import SwiftUI

struct MeasurementFormView: View {
    @ObservedObject var viewModel: MeasurementViewModel
    @Environment(\.dismiss) private var dismiss

    let measurement: Measurement?

    @State private var date: Date = Date()
    @State private var bodyWeight: String = ""
    @State private var bodyFat: String = ""
    @State private var neck: String = ""
    @State private var shoulders: String = ""
    @State private var chest: String = ""
    @State private var waist: String = ""
    @State private var hips: String = ""
    @State private var armLeft: String = ""
    @State private var armRight: String = ""
    @State private var forearmLeft: String = ""
    @State private var forearmRight: String = ""
    @State private var thighLeft: String = ""
    @State private var thighRight: String = ""
    @State private var calfLeft: String = ""
    @State private var calfRight: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false

    init(viewModel: MeasurementViewModel, measurement: Measurement? = nil) {
        self.viewModel = viewModel
        self.measurement = measurement
    }

    var isEditing: Bool {
        measurement != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Body Composition") {
                    MeasurementField(label: "Weight", value: $bodyWeight, unit: "kg")
                    MeasurementField(label: "Body Fat", value: $bodyFat, unit: "%")
                }

                Section("Upper Body (cm)") {
                    MeasurementField(label: "Neck", value: $neck, unit: "cm")
                    MeasurementField(label: "Shoulders", value: $shoulders, unit: "cm")
                    MeasurementField(label: "Chest", value: $chest, unit: "cm")
                }

                Section("Arms (cm)") {
                    HStack {
                        MeasurementField(label: "L Arm", value: $armLeft, unit: "")
                        MeasurementField(label: "R Arm", value: $armRight, unit: "")
                    }
                    HStack {
                        MeasurementField(label: "L Forearm", value: $forearmLeft, unit: "")
                        MeasurementField(label: "R Forearm", value: $forearmRight, unit: "")
                    }
                }

                Section("Core (cm)") {
                    MeasurementField(label: "Waist", value: $waist, unit: "cm")
                    MeasurementField(label: "Hips", value: $hips, unit: "cm")
                }

                Section("Legs (cm)") {
                    HStack {
                        MeasurementField(label: "L Thigh", value: $thighLeft, unit: "")
                        MeasurementField(label: "R Thigh", value: $thighRight, unit: "")
                    }
                    HStack {
                        MeasurementField(label: "L Calf", value: $calfLeft, unit: "")
                        MeasurementField(label: "R Calf", value: $calfRight, unit: "")
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle(isEditing ? "Edit Measurement" : "New Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMeasurement()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let m = measurement {
                    date = m.date
                    bodyWeight = m.bodyWeight.map { String(format: "%.1f", $0) } ?? ""
                    bodyFat = m.bodyFat.map { String(format: "%.1f", $0) } ?? ""
                    neck = m.neck.map { String(format: "%.1f", $0) } ?? ""
                    shoulders = m.shoulders.map { String(format: "%.1f", $0) } ?? ""
                    chest = m.chest.map { String(format: "%.1f", $0) } ?? ""
                    waist = m.waist.map { String(format: "%.1f", $0) } ?? ""
                    hips = m.hips.map { String(format: "%.1f", $0) } ?? ""
                    armLeft = m.armLeft.map { String(format: "%.1f", $0) } ?? ""
                    armRight = m.armRight.map { String(format: "%.1f", $0) } ?? ""
                    forearmLeft = m.forearmLeft.map { String(format: "%.1f", $0) } ?? ""
                    forearmRight = m.forearmRight.map { String(format: "%.1f", $0) } ?? ""
                    thighLeft = m.thighLeft.map { String(format: "%.1f", $0) } ?? ""
                    thighRight = m.thighRight.map { String(format: "%.1f", $0) } ?? ""
                    calfLeft = m.calfLeft.map { String(format: "%.1f", $0) } ?? ""
                    calfRight = m.calfRight.map { String(format: "%.1f", $0) } ?? ""
                    notes = m.notes ?? ""
                }
            }
        }
    }

    private func saveMeasurement() {
        isSaving = true

        var newMeasurement = measurement ?? Measurement(date: date)
        newMeasurement.date = date
        newMeasurement.bodyWeight = Double(bodyWeight)
        newMeasurement.bodyFat = Double(bodyFat)
        newMeasurement.neck = Double(neck)
        newMeasurement.shoulders = Double(shoulders)
        newMeasurement.chest = Double(chest)
        newMeasurement.waist = Double(waist)
        newMeasurement.hips = Double(hips)
        newMeasurement.armLeft = Double(armLeft)
        newMeasurement.armRight = Double(armRight)
        newMeasurement.forearmLeft = Double(forearmLeft)
        newMeasurement.forearmRight = Double(forearmRight)
        newMeasurement.thighLeft = Double(thighLeft)
        newMeasurement.thighRight = Double(thighRight)
        newMeasurement.calfLeft = Double(calfLeft)
        newMeasurement.calfRight = Double(calfRight)
        newMeasurement.notes = notes.isEmpty ? nil : notes

        Task {
            if await viewModel.saveMeasurement(newMeasurement) {
                dismiss()
            }
            isSaving = false
        }
    }
}

struct MeasurementField: View {
    let label: String
    @Binding var value: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            if !unit.isEmpty {
                Text(unit)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
            }
        }
    }
}
