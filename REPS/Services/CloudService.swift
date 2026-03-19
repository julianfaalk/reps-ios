import AuthenticationServices
import CryptoKit
import Foundation
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum WorkoutAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)
    case decodingError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Die API-URL ist ungueltig."
        case .unauthorized:
            return "Deine Sitzung ist abgelaufen. Bitte melde dich erneut an."
        case .serverError(let message):
            return message
        case .decodingError:
            return "Die Serverantwort konnte nicht gelesen werden."
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

enum WorkoutKeychainService {
    private static let service = "com.julianfalk.reps"
    private static let tokenKey = "auth_token"

    static func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class WorkoutAPIService {
    static let shared = WorkoutAPIService()

    struct AuthResponse: Codable {
        let token: String
        let user: WorkoutCloudUser
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: string) {
                return date
            }

            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not decode date: \(string)"
            )
        }
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    func authApple(idToken: String) async throws -> AuthResponse {
        try await post("/auth/apple", body: ["idToken": idToken], requiresAuth: false)
    }

    func authGoogle(idToken: String) async throws -> AuthResponse {
        try await post("/auth/google", body: ["idToken": idToken], requiresAuth: false)
    }

    func sendMagicLink(email: String) async throws {
        let _: [String: String] = try await post("/auth/email/send", body: ["email": email], requiresAuth: false)
    }

    func verifyMagicLink(token: String) async throws -> AuthResponse {
        try await post("/auth/email/verify", body: ["token": token], requiresAuth: false)
    }

    func fetchMe() async throws -> WorkoutCloudUser {
        try await get("/auth/me")
    }

    func syncMe(_ request: WorkoutSyncRequest) async throws -> WorkoutCloudUser {
        try await post("/users/me/sync", body: request)
    }

    func upsertCurrentDevice(_ request: WorkoutDeviceRegistrationRequest) async throws {
        let _: [String: String] = try await put("/users/me/devices/current", body: request)
    }

    func fetchFriends() async throws -> WorkoutFriendsResponse {
        try await get("/friends")
    }

    func sendFriendRequest(friendCode: String) async throws {
        struct RequestBody: Encodable {
            let friendCode: String
        }
        let _: [String: String] = try await post("/friends/requests", body: RequestBody(friendCode: friendCode))
    }

    func acceptFriendRequest(requestID: String) async throws {
        let _: [String: String] = try await post("/friends/requests/\(requestID)/accept", body: EmptyBody())
    }

    func deleteFriend(friendID: String) async throws {
        let _: [String: String] = try await delete("/friends/\(friendID)")
    }

    func fetchLeaderboard() async throws -> [WorkoutLeaderboardEntry] {
        try await get("/friends/leaderboard")
    }

    func syncSubscription(originalTransactionId: String, productId: String, expiresDate: Date?) async throws {
        struct Body: Encodable {
            let originalTransactionId: String
            let productId: String
            let expiresDate: Date?
        }

        let _: [String: String] = try await post(
            "/subscriptions/sync",
            body: Body(
                originalTransactionId: originalTransactionId,
                productId: productId,
                expiresDate: expiresDate
            )
        )
    }

    func fetchSubscriptionStatus() async throws -> WorkoutSubscriptionStatus {
        try await get("/subscriptions/status")
    }

    func deleteAccount() async throws {
        let _: [String: String] = try await delete("/users/me/account")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", requiresAuth: true, body: nil)
        return try await execute(request)
    }

    private func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> T {
        let data = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "POST", requiresAuth: requiresAuth, body: data)
        return try await execute(request)
    }

    private func put<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> T {
        let data = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "PUT", requiresAuth: requiresAuth, body: data)
        return try await execute(request)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "DELETE", requiresAuth: true, body: nil)
        return try await execute(request)
    }

    private func buildRequest(
        path: String,
        method: String,
        requiresAuth: Bool,
        body: Data?
    ) throws -> URLRequest {
        guard let url = URL(string: AppConfig.apiBaseURL + path) else {
            throw WorkoutAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth {
            guard let token = WorkoutKeychainService.getToken() else {
                throw WorkoutAPIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WorkoutAPIError.serverError("Keine gueltige Serverantwort.")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw WorkoutAPIError.decodingError
                }
            case 401:
                if let payload = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = payload["error"],
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw WorkoutAPIError.serverError(message)
                }
                if request.value(forHTTPHeaderField: "Authorization") == nil {
                    throw WorkoutAPIError.serverError("Anmeldung fehlgeschlagen.")
                }
                throw WorkoutAPIError.unauthorized
            default:
                if let payload = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = payload["error"] {
                    throw WorkoutAPIError.serverError(message)
                }
                throw WorkoutAPIError.serverError("Serverfehler \(httpResponse.statusCode)")
            }
        } catch let error as WorkoutAPIError {
            throw error
        } catch {
            throw WorkoutAPIError.networkError(error)
        }
    }
}

private struct EmptyBody: Encodable {}

@MainActor
final class WorkoutAuthService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = WorkoutAPIService.shared
    private var currentNonce: String?

    var isLoggedIn: Bool {
        WorkoutKeychainService.getToken() != nil
    }

    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async -> WorkoutCloudUser? {
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            errorMessage = "Apple konnte kein gueltiges Login-Token liefern."
            return nil
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.authApple(idToken: idTokenString)
            WorkoutKeychainService.saveToken(response.token)
            isLoading = false
            return response.user
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    func signInWithGoogle() async -> WorkoutCloudUser? {
        guard AppConfig.isGoogleSignInConfigured else {
            errorMessage = "Google Sign-In ist fuer REPS noch nicht konfiguriert."
            return nil
        }

        #if canImport(GoogleSignIn)
        isLoading = true
        errorMessage = nil

        guard let googleClientID = AppConfig.googleClientID,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Google Sign-In konnte nicht gestartet werden."
            isLoading = false
            return nil
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: googleClientID,
            serverClientID: AppConfig.googleServerClientID
        )

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google konnte kein Login-Token liefern."
                isLoading = false
                return nil
            }
            let response = try await api.authGoogle(idToken: idToken)
            WorkoutKeychainService.saveToken(response.token)
            isLoading = false
            return response.user
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
        #else
        errorMessage = "Google Sign-In Package ist nicht eingebunden."
        return nil
        #endif
    }

    func sendMagicLink(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            try await api.sendMagicLink(email: email)
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func verifyMagicLink(token: String) async -> WorkoutCloudUser? {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.verifyMagicLink(token: token)
            WorkoutKeychainService.saveToken(response.token)
            isLoading = false
            return response.user
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    func restoreSession() async -> WorkoutCloudUser? {
        guard WorkoutKeychainService.getToken() != nil else { return nil }
        do {
            return try await api.fetchMe()
        } catch {
            WorkoutKeychainService.deleteToken()
            return nil
        }
    }

    func signOut() {
        WorkoutKeychainService.deleteToken()
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce.")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
