import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(
            date: Date(),
            schedule: nil,
            templateName: "Push Day",
            isRestDay: false,
            isWorkoutActive: false,
            restTimeRemaining: nil,
            currentExercise: nil,
            setProgress: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        let entry = WorkoutEntry(
            date: Date(),
            schedule: nil,
            templateName: "Push Day",
            isRestDay: false,
            isWorkoutActive: false,
            restTimeRemaining: nil,
            currentExercise: nil,
            setProgress: nil
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        // In a real implementation, this would read from a shared app group
        // For now, we'll show a placeholder
        let currentDate = Date()
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: currentDate) - 1

        // Create entries for the next hour
        var entries: [WorkoutEntry] = []

        let entry = WorkoutEntry(
            date: currentDate,
            schedule: nil,
            templateName: nil,
            isRestDay: false,
            isWorkoutActive: false,
            restTimeRemaining: nil,
            currentExercise: nil,
            setProgress: nil
        )
        entries.append(entry)

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// MARK: - Entry

struct WorkoutEntry: TimelineEntry {
    let date: Date
    let schedule: ScheduleDay?
    let templateName: String?
    let isRestDay: Bool
    let isWorkoutActive: Bool
    let restTimeRemaining: Int?
    let currentExercise: String?
    let setProgress: String?
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.isWorkoutActive {
                // During workout - show rest timer
                if let restTime = entry.restTimeRemaining {
                    VStack(spacing: 4) {
                        Text("Rest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatWidgetDuration(restTime))
                            .font(.title)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title)
                        Text("Workout Active")
                            .font(.caption)
                    }
                }
            } else {
                // Default - show next workout
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date(), style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if entry.isRestDay {
                        HStack {
                            Image(systemName: "bed.double.fill")
                            Text("Rest Day")
                        }
                        .font(.headline)
                        .foregroundColor(.orange)
                    } else if let templateName = entry.templateName {
                        Text(templateName)
                            .font(.headline)
                            .lineLimit(2)
                    } else {
                        Text("No workout")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: WorkoutEntry

    var body: some View {
        HStack {
            if entry.isWorkoutActive {
                // During workout
                VStack(alignment: .leading, spacing: 8) {
                    if let restTime = entry.restTimeRemaining {
                        HStack {
                            Image(systemName: "hourglass")
                            Text("Rest: \(formatWidgetDuration(restTime))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        .foregroundColor(.orange)
                    }

                    if let exercise = entry.currentExercise {
                        Text(exercise)
                            .font(.headline)
                    }

                    if let progress = entry.setProgress {
                        Text(progress)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

            } else {
                // Default - show today + next days
                VStack(alignment: .leading, spacing: 8) {
                    Text("This Week")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if entry.isRestDay {
                        HStack {
                            Image(systemName: "bed.double.fill")
                            Text("Rest Day")
                        }
                        .font(.headline)
                        .foregroundColor(.orange)
                    } else if let templateName = entry.templateName {
                        HStack {
                            Image(systemName: "figure.strengthtraining.traditional")
                            Text(templateName)
                        }
                        .font(.headline)
                    } else {
                        Text("No workout scheduled")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large Widget View

struct LargeWidgetView: View {
    let entry: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Schedule")
                .font(.headline)

            // Week days
            ForEach(0..<7, id: \.self) { day in
                HStack {
                    Text(dayName(for: day))
                        .font(.caption)
                        .frame(width: 40, alignment: .leading)

                    Spacer()

                    Text("...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            Spacer()

            if entry.isWorkoutActive {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("Workout in progress")
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func dayName(for index: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[index]
    }
}

// MARK: - Widget Configuration

struct WorkoutWidget: Widget {
    let kind: String = "WorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            WorkoutWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Workout")
        .description("View your scheduled workouts and track rest timers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WorkoutWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WorkoutEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Helper

private func formatWidgetDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", minutes, secs)
}

// MARK: - Schedule Day (duplicated for widget target)

struct ScheduleDay {
    var dayOfWeek: Int
    var templateName: String?
    var isRestDay: Bool
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    WorkoutWidget()
} timeline: {
    WorkoutEntry(
        date: Date(),
        schedule: nil,
        templateName: "Push Day",
        isRestDay: false,
        isWorkoutActive: false,
        restTimeRemaining: nil,
        currentExercise: nil,
        setProgress: nil
    )
}
