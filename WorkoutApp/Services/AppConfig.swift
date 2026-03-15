import Foundation

enum AppConfig {
    static let apiBaseURL = "https://julianfalk.dev/workout-api"
    static let supportEmail = "support@julianfalk.dev"
    static let appScheme = "workoutapp"
    static let privacyURL = URL(string: "\(apiBaseURL)/privacy")!
    static let termsURL = URL(string: "\(apiBaseURL)/terms")!
    static let premiumProductIDs = [
        "com.julianfalk.workoutapp.premium.monthly",
        "com.julianfalk.workoutapp.premium.yearly",
    ]

    // Fill these once the dedicated Google OAuth client for com.julianfalk.WorkoutApp exists.
    static let googleClientID: String? = nil
    static let googleServerClientID: String? = nil

    static var isGoogleSignInConfigured: Bool {
        guard let googleClientID else { return false }
        return !googleClientID.isEmpty
    }
}
