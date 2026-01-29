import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock Screen presentation
            WorkoutLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.templateName)
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(context.state.currentExercise)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.setProgress)
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("\(context.state.totalSetsCompleted) sets")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.isResting {
                        VStack(spacing: 4) {
                            Text("REST")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(formatLADuration(context.state.restTimeRemaining))
                                .font(.system(.title, design: .rounded))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.orange)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.secondary)
                        Text("Workout: \(formatLADuration(context.state.workoutDuration))")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                if context.state.isResting {
                    Image(systemName: "hourglass")
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(.accentColor)
                }
            } compactTrailing: {
                if context.state.isResting {
                    Text(formatLADuration(context.state.restTimeRemaining))
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.orange)
                } else {
                    Text(context.state.setProgress)
                        .font(.caption)
                        .fontWeight(.bold)
                }
            } minimal: {
                if context.state.isResting {
                    Image(systemName: "hourglass")
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
            }
        }
    }
}

// MARK: - Lock Screen View for Live Activity

struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.templateName)
                        .font(.headline)
                    Text(context.state.currentExercise)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.state.setProgress)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(formatLADuration(context.state.workoutDuration))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            if context.state.isResting {
                HStack {
                    Image(systemName: "hourglass")
                    Text("Rest")
                        .font(.caption)
                    Spacer()
                    Text(formatLADuration(context.state.restTimeRemaining))
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
                .padding()
                .background(Color.orange.opacity(0.15))
                .cornerRadius(12)
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.7))
    }
}

// MARK: - Helper

private func formatLADuration(_ seconds: Int) -> String {
    let mins = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", mins, secs)
}
