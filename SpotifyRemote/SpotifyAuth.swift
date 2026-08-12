import AppKit
import Combine
import CryptoKit
import Foundation

@MainActor
final class SpotifyAuth: ObservableObject {
    @Published var isLoggedIn = false

    private var verifier: String?
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var state: String?

    init() {
        isLoggedIn = Keychain.read("refresh_token") != nil
    }

    // MARK: - Login

    /// Opens the Spotify authorization page in the default browser.
    func startLogin() {
        let v = Self.makeVerifier()
        verifier = v
        let s = Self.makeVerifier()
        state = s

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.makeChallenge(from: v)),
            URLQueryItem(name: "scope", value: Config.scopes),
            URLQueryItem(name: "state", value: s)
        ]

        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Called when the browser redirects back into the app.
    func handleCallback(_ url: URL) async {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        if let error = items?.first(where: { $0.name == "error" })?.value {
            print("[Auth] Authorization denied: \(error)")
            return
        }

        guard let returned = items?.first(where: { $0.name == "state" })?.value,
              returned == state else {
            print("[Auth] State mismatch — possible interception")
            return
        }
        
        guard let code = items?.first(where: { $0.name == "code" })?.value,
              let v = verifier else {
            print("[Auth] Callback missing code or verifier")
            return
        }

        await requestToken(fields: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Config.redirectURI,
            "client_id": Config.clientID,
            "code_verifier": v
        ])
    }

    // MARK: - Token

    /// Returns a valid access token, refreshing it if needed.
    func validToken() async -> String? {
        if let token = accessToken, expiresAt > Date().addingTimeInterval(60) {
            return token
        }
        guard let refresh = Keychain.read("refresh_token") else { return nil }

        await requestToken(fields: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": Config.clientID
        ])
        return accessToken
    }

    func logout() {
        Keychain.delete("refresh_token")
        accessToken = nil
        expiresAt = .distantPast
        isLoggedIn = false
    }

    // MARK: - Internals

    private func requestToken(fields: [String: String]) async {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")

        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                print("[Auth] Token request failed:",
                      String(data: data, encoding: .utf8) ?? "")
                // A rejected refresh token means the session is dead.
                if Keychain.read("refresh_token") != nil, accessToken == nil {
                    logout()
                }
                return
            }

            accessToken = token
            let seconds = json["expires_in"] as? Double ?? 3600
            expiresAt = Date().addingTimeInterval(seconds)

            if let refresh = json["refresh_token"] as? String {
                Keychain.save(refresh, for: "refresh_token")
            }
            isLoggedIn = true
        } catch {
            print("[Auth] Network error:", error)
        }
    }

    private static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func makeChallenge(from verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
