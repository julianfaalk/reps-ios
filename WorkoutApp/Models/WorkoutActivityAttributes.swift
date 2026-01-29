import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var workoutDuration: Int
        var isResting: Bool
        var restTimeRemaining: Int
        var currentExercise: String
        var setProgress: String // e.g. "Set 3/4"
        var totalSetsCompleted: Int
    }

    var templateName: String
    var startedAt: Date
}
