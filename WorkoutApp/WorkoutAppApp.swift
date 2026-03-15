import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct WorkoutAppApp: App {
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var sessionViewModel = AppSessionViewModel()
    @StateObject private var storeManager = StoreManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutViewModel)
                .environmentObject(sessionViewModel)
                .environmentObject(storeManager)
                .onOpenURL { url in
                    if url.scheme == AppConfig.appScheme {
                        Task {
                            await sessionViewModel.handleIncomingURL(url)
                        }
                    } else {
                        #if canImport(GoogleSignIn)
                        GIDSignIn.sharedInstance.handle(url)
                        #endif
                    }
                }
        }
    }
}
