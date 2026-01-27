import Foundation
import SwiftUI

@MainActor
class MeasurementViewModel: ObservableObject {
    @Published var measurements: [Measurement] = []
    @Published var currentMeasurement: MeasurementWithPhotos?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = DatabaseService.shared

    init() {
        Task {
            await loadMeasurements()
        }
    }

    func loadMeasurements() async {
        isLoading = true
        do {
            measurements = try db.fetchAllMeasurements()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMeasurement(id: UUID) async {
        isLoading = true
        do {
            currentMeasurement = try db.fetchMeasurementWithPhotos(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveMeasurement(_ measurement: Measurement) async -> Bool {
        do {
            try db.saveMeasurement(measurement)
            await loadMeasurements()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteMeasurement(_ measurement: Measurement) async -> Bool {
        do {
            try db.deleteMeasurement(measurement)
            await loadMeasurements()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addPhoto(measurementId: UUID, imageData: Data, type: PhotoType?) async -> Bool {
        do {
            let photo = ProgressPhoto(
                measurementId: measurementId,
                photoData: imageData,
                photoType: type
            )
            try db.saveProgressPhoto(photo)
            await loadMeasurement(id: measurementId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePhoto(_ photo: ProgressPhoto) async -> Bool {
        do {
            try db.deleteProgressPhoto(photo)
            await loadMeasurement(id: photo.measurementId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var latestWeight: Double? {
        measurements.first?.bodyWeight
    }

    var weightChange: Double? {
        guard measurements.count >= 2,
              let latest = measurements.first?.bodyWeight,
              let previous = measurements.dropFirst().first?.bodyWeight else {
            return nil
        }
        return latest - previous
    }
}
