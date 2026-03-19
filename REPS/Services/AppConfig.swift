import Foundation

enum AppConfig {
    struct PremiumProductFallback {
        let id: String
        let usdPrice: Decimal
    }

    static let apiBaseURL = "https://julianfalk.dev/workout-api"
    static let supportEmail = "support@julianfalk.dev"
    static let appScheme = "reps"
    static let privacyURL = URL(string: "\(apiBaseURL)/privacy")!
    static let termsURL = URL(string: "\(apiBaseURL)/terms")!

    static let premiumMonthlyProductID = "com.julianfalk.reps.premium.monthly"
    static let premiumYearlyProductID = "com.julianfalk.reps.premium.yearly"
    static let premiumLifetimeProductID = "com.julianfalk.reps.premium.forever"

    static let premiumProductIDs = [
        premiumMonthlyProductID,
        premiumYearlyProductID,
        premiumLifetimeProductID,
    ]
    static let premiumProductFallbacks: [String: PremiumProductFallback] = [
        premiumMonthlyProductID: PremiumProductFallback(id: premiumMonthlyProductID, usdPrice: 4.99),
        premiumYearlyProductID: PremiumProductFallback(id: premiumYearlyProductID, usdPrice: 29.99),
        premiumLifetimeProductID: PremiumProductFallback(id: premiumLifetimeProductID, usdPrice: 79.99),
    ]
    static let yearlyTrialDays = 7
    static let maxFreeCustomTemplates = 3
    static let builtInTemplateNames: Set<String> = [
        "Push (Brust, Trizeps, vordere Schulter)",
        "Pull (Rücken, Bizeps, hintere Schulter)",
        "Legs (Beine, unterer Rücken)",
        "Schultern, Arme & Core",
    ]

    static let googleClientID = infoString(for: "GIDClientID") ?? infoString(for: "REPSGoogleClientID")
    static let googleServerClientID = infoString(for: "REPSGoogleServerClientID")
    static let googleReversedClientID = infoString(for: "REPSGoogleReversedClientID")

    static var isGoogleSignInConfigured: Bool {
        googleClientID != nil && googleReversedClientID != nil
    }

    static func fallbackDisplayPrice(for productID: String, locale: Locale = .current) -> String? {
        guard let fallback = premiumProductFallbacks[productID] else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = locale.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: NSDecimalNumber(decimal: fallback.usdPrice))
    }

    private static func infoString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
