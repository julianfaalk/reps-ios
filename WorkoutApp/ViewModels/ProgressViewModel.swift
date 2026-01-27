import Foundation
import SwiftUI

@MainActor
class ProgressViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var selectedExercise: Exercise?
    @Published var exerciseProgressData: [(date: Date, maxWeight: Double, totalVolume: Double)] = []
    @Published var bodyWeightData: [(date: Date, weight: Double)] = []
    @Published var personalRecords: [PersonalRecordWithExercise] = []
    @Published var selectedTimeRange: TimeRange = .threeMonths {
        didSet { Task { await loadData() } }
    }
    @Published var chartType: ChartType = .maxWeight
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = DatabaseService.shared

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "4 Weeks"
        case threeMonths = "3 Months"
        case year = "1 Year"
        case all = "All Time"

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: Date())
            case .month:
                return calendar.date(byAdding: .day, value: -28, to: Date())
            case .threeMonths:
                return calendar.date(byAdding: .month, value: -3, to: Date())
            case .year:
                return calendar.date(byAdding: .year, value: -1, to: Date())
            case .all:
                return nil
            }
        }
    }

    enum ChartType: String, CaseIterable {
        case maxWeight = "Max Weight"
        case volume = "Volume"
    }

    init() {
        Task {
            await loadExercises()
            await loadPersonalRecords()
        }
    }

    func loadExercises() async {
        do {
            exercises = try db.fetchAllExercises()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadData() async {
        await loadExerciseProgress()
        await loadBodyWeightProgress()
    }

    func selectExercise(_ exercise: Exercise) async {
        selectedExercise = exercise
        await loadExerciseProgress()
    }

    func loadExerciseProgress() async {
        guard let exercise = selectedExercise else {
            exerciseProgressData = []
            return
        }

        isLoading = true
        do {
            exerciseProgressData = try db.fetchExerciseProgress(
                exerciseId: exercise.id,
                from: selectedTimeRange.startDate
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadBodyWeightProgress() async {
        isLoading = true
        do {
            bodyWeightData = try db.fetchBodyWeightProgress(
                from: selectedTimeRange.startDate
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadPersonalRecords() async {
        do {
            personalRecords = try db.fetchAllPersonalRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func getPR(for exerciseId: UUID) -> PersonalRecord? {
        personalRecords.first { $0.record.exerciseId == exerciseId }?.record
    }

    var chartData: [(date: Date, value: Double)] {
        switch chartType {
        case .maxWeight:
            return exerciseProgressData.map { ($0.date, $0.maxWeight) }
        case .volume:
            return exerciseProgressData.map { ($0.date, $0.totalVolume) }
        }
    }
}
