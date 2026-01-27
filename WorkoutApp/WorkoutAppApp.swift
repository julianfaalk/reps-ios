import SwiftUI

@main
struct WorkoutAppApp: App {
    @StateObject private var workoutViewModel = WorkoutViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutViewModel)
        }
    }
}
