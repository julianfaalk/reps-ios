import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workoutViewModel: WorkoutViewModel
    @EnvironmentObject var sessionViewModel: AppSessionViewModel
    @State private var selectedTab = 0

    var body: some View {
        Group {
            switch sessionViewModel.state {
            case .loading:
                ProgressView("Workout Cloud wird geladen ...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            case .signedOut:
                AuthGateView()
            case .profileSetup:
                ProfileSetupView()
            case .ready:
                WorkoutMainTabView(selectedTab: $selectedTab)
                    .environmentObject(workoutViewModel)
            }
        }
        .alert("Cloud-Fehler", isPresented: Binding(
            get: { sessionViewModel.errorMessage != nil },
            set: { if !$0 { sessionViewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                sessionViewModel.errorMessage = nil
            }
        } message: {
            Text(sessionViewModel.errorMessage ?? "")
        }
        .task(id: sessionViewModel.state) {
            if sessionViewModel.state == .ready {
                await sessionViewModel.syncSnapshot()
            }
        }
    }
}

private struct WorkoutMainTabView: View {
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(0)

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(1)

            ExerciseListView()
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell")
                }
                .tag(2)

            ProgressTabView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutViewModel())
        .environmentObject(AppSessionViewModel())
        .environmentObject(StoreManager.shared)
}
