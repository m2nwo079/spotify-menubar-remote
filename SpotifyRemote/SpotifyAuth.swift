import AppKit
import CryptoKit
import Foundation
import Combine

@MainActor
final class SpotifyAuth: ObservableObject {
    @Published var isLoggedIn = false

    private var verifier: String?
    private var accessToken: String?
    private var expiresAt = Date.distantPast

    init() {
        isLoggedIn = Keychain.read("refresh_token") != nil
    }

    // MARK

    func startLogin() {
        let v = Self.makeVerifier()
        verifier = v

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.makeChallenge(from: v)),
            URLQueryItem(name: "scope", value: Config.scopes)
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK

    func handleCallback(_ url: URL) async {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
              let v = verifier else { return }

        await requestToken(fields: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Config.redirectURI,
            "client_id": Config.clientID,
            "code_verifier": v
        ])
    }

    // MARK

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

    // MARK

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
                print("토큰 발급 실패:", String(data: data, encoding: .utf8) ?? "")
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
            print("Network Error:", error)
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
