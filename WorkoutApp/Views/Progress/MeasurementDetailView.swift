import SwiftUI
import PhotosUI

struct MeasurementDetailView: View {
    let measurementId: UUID
    @ObservedObject var viewModel: MeasurementViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var selectedPhotoType: PhotoType = .front
    @State private var selectedPhotoItem: PhotosPickerItem?

    var measurement: Measurement? {
        viewModel.currentMeasurement?.measurement
    }

    var photos: [ProgressPhoto] {
        viewModel.currentMeasurement?.photos ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if let measurement = measurement {
                    List {
                        // Body composition
                        if measurement.bodyWeight != nil || measurement.bodyFat != nil {
                            Section("Body Composition") {
                                if let weight = measurement.bodyWeight {
                                    MeasurementRow(label: "Weight", value: String(format: "%.1f", weight), unit: "kg")
                                }
                                if let bf = measurement.bodyFat {
                                    MeasurementRow(label: "Body Fat", value: String(format: "%.1f", bf), unit: "%")
                                }
                            }
                        }

                        // Upper body
                        if hasUpperBodyMeasurements(measurement) {
                            Section("Upper Body") {
                                if let v = measurement.neck { MeasurementRow(label: "Neck", value: String(format: "%.1f", v), unit: "cm") }
                                if let v = measurement.shoulders { MeasurementRow(label: "Shoulders", value: String(format: "%.1f", v), unit: "cm") }
                                if let v = measurement.chest { MeasurementRow(label: "Chest", value: String(format: "%.1f", v), unit: "cm") }
                            }
                        }

                        // Arms
                        if hasArmMeasurements(measurement) {
                            Section("Arms") {
                                if measurement.armLeft != nil || measurement.armRight != nil {
                                    HStack {
                                        if let v = measurement.armLeft { Text("L: \(String(format: "%.1f", v)) cm") }
                                        Spacer()
                                        if let v = measurement.armRight { Text("R: \(String(format: "%.1f", v)) cm") }
                                    }
                                }
                                if measurement.forearmLeft != nil || measurement.forearmRight != nil {
                                    HStack {
                                        Text("Forearm")
                                        Spacer()
                                        if let v = measurement.forearmLeft { Text("L: \(String(format: "%.1f", v))") }
                                        if let v = measurement.forearmRight { Text("R: \(String(format: "%.1f", v))") }
                                    }
                                }
                            }
                        }

                        // Core
                        if measurement.waist != nil || measurement.hips != nil {
                            Section("Core") {
                                if let v = measurement.waist { MeasurementRow(label: "Waist", value: String(format: "%.1f", v), unit: "cm") }
                                if let v = measurement.hips { MeasurementRow(label: "Hips", value: String(format: "%.1f", v), unit: "cm") }
                            }
                        }

                        // Legs
                        if hasLegMeasurements(measurement) {
                            Section("Legs") {
                                if measurement.thighLeft != nil || measurement.thighRight != nil {
                                    HStack {
                                        Text("Thigh")
                                        Spacer()
                                        if let v = measurement.thighLeft { Text("L: \(String(format: "%.1f", v))") }
                                        if let v = measurement.thighRight { Text("R: \(String(format: "%.1f", v))") }
                                    }
                                }
                                if measurement.calfLeft != nil || measurement.calfRight != nil {
                                    HStack {
                                        Text("Calf")
                                        Spacer()
                                        if let v = measurement.calfLeft { Text("L: \(String(format: "%.1f", v))") }
                                        if let v = measurement.calfRight { Text("R: \(String(format: "%.1f", v))") }
                                    }
                                }
                            }
                        }

                        // Notes
                        if let notes = measurement.notes, !notes.isEmpty {
                            Section("Notes") {
                                Text(notes)
                            }
                        }

                        // Progress Photos
                        Section("Progress Photos") {
                            if photos.isEmpty {
                                Text("No photos added")
                                    .foregroundColor(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(photos) { photo in
                                            if let uiImage = UIImage(data: photo.photoData) {
                                                VStack {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 100, height: 150)
                                                        .clipped()
                                                        .cornerRadius(8)

                                                    if let type = photo.photoType {
                                                        Text(type.displayName)
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Menu {
                                ForEach(PhotoType.allCases, id: \.self) { type in
                                    Button(type.displayName) {
                                        selectedPhotoType = type
                                        showingPhotoPicker = true
                                    }
                                }
                            } label: {
                                Label("Add Photo", systemImage: "plus.circle")
                            }
                        }

                        // Actions
                        Section {
                            Button("Edit Measurement") {
                                showingEditSheet = true
                            }

                            Button("Delete Measurement", role: .destructive) {
                                showingDeleteAlert = true
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(measurement?.date.formatted(date: .abbreviated, time: .omitted) ?? "Measurement")
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
                    await viewModel.loadMeasurement(id: measurementId)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let m = measurement {
                    MeasurementFormView(viewModel: viewModel, measurement: m)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        await viewModel.addPhoto(measurementId: measurementId, imageData: data, type: selectedPhotoType)
                    }
                }
            }
            .alert("Delete Measurement?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let m = measurement {
                        Task {
                            if await viewModel.deleteMeasurement(m) {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    private func hasUpperBodyMeasurements(_ m: Measurement) -> Bool {
        m.neck != nil || m.shoulders != nil || m.chest != nil
    }

    private func hasArmMeasurements(_ m: Measurement) -> Bool {
        m.armLeft != nil || m.armRight != nil || m.forearmLeft != nil || m.forearmRight != nil
    }

    private func hasLegMeasurements(_ m: Measurement) -> Bool {
        m.thighLeft != nil || m.thighRight != nil || m.calfLeft != nil || m.calfRight != nil
    }
}

struct MeasurementRow: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value) \(unit)")
                .foregroundColor(.secondary)
        }
    }
}
