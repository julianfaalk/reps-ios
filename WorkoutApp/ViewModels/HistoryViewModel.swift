import Foundation
import SwiftUI

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var sessions: [SessionWithDetails] = []
    @Published var filteredSessions: [SessionWithDetails] = []
    @Published var searchText: String = "" {
        didSet { filterSessions() }
    }
    @Published var selectedDateRange: DateRange = .all {
        didSet { filterSessions() }
    }
    @Published var selectedTemplateId: UUID? = nil {
        didSet { filterSessions() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = DatabaseService.shared

    enum DateRange: String, CaseIterable {
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        case threeMonths = "Last 3 Months"
        case year = "Last Year"
        case all = "All Time"

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: Date())
            case .month:
                return calendar.date(byAdding: .day, value: -30, to: Date())
            case .threeMonths:
                return calendar.date(byAdding: .month, value: -3, to: Date())
            case .year:
                return calendar.date(byAdding: .year, value: -1, to: Date())
            case .all:
                return nil
            }
        }
    }

    init() {
        Task {
            await loadSessions()
        }
    }

    func loadSessions() async {
        isLoading = true
        do {
            sessions = try db.fetchRecentSessions(limit: 100)
            filterSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func filterSessions() {
        var result = sessions

        // Filter by date range
        if let startDate = selectedDateRange.startDate {
            result = result.filter { $0.session.startedAt >= startDate }
        }

        // Filter by template
        if let templateId = selectedTemplateId {
            result = result.filter { $0.session.templateId == templateId }
        }

        // Filter by search text (exercise name)
        if !searchText.isEmpty {
            result = result.filter { session in
                session.sets.contains { $0.exercise.name.localizedCaseInsensitiveContains(searchText) }
            }
        }

        filteredSessions = result
    }

    func deleteSession(_ session: WorkoutSession) async -> Bool {
        do {
            try db.deleteSession(session)
            await loadSessions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func getSessionDetails(id: UUID) async -> SessionWithDetails? {
        do {
            return try db.fetchSessionWithDetails(id: id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateSession(_ session: WorkoutSession) async -> Bool {
        do {
            try db.saveSession(session)
            await loadSessions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateSet(_ set: SessionSet) async -> Bool {
        do {
            try db.saveSessionSet(set)
            await loadSessions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSet(_ set: SessionSet) async -> Bool {
        do {
            try db.deleteSessionSet(set)
            await loadSessions()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
