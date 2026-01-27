import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    var startOfWeek: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    var dayOfWeek: Int {
        Calendar.current.component(.weekday, from: self) - 1 // 0-indexed
    }
}

// MARK: - Double Extensions

extension Double {
    var formattedWeight: String {
        if self.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(self)) kg"
        } else {
            return String(format: "%.1f kg", self)
        }
    }

    var formattedDistance: String {
        String(format: "%.2f km", self)
    }

    var formattedPercentage: String {
        String(format: "%.1f%%", self)
    }
}

// MARK: - Int Extensions

extension Int {
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - View Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Color Extensions

extension Color {
    static let exerciseReps = Color.blue
    static let exerciseTimed = Color.orange
    static let restDay = Color.orange
    static let workoutDay = Color.accentColor
    static let prGold = Color.yellow
}

// MARK: - Array Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - UUID Extensions

extension UUID: @retroactive RawRepresentable {
    public var rawValue: String {
        uuidString
    }

    public init?(rawValue: String) {
        self.init(uuidString: rawValue)
    }
}
