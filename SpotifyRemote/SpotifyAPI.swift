import Foundation

struct NowPlaying {
    var title: String
    var artist: String
    var isPlaying: Bool
    var trackURI: String?
    var artworkURL: String?
    var progressMs: Int
    var durationMs: Int
    var volume: Int
    var volumeSupported: Bool
    var deviceName: String?
}

@MainActor
final class SpotifyAPI {
    private let auth: SpotifyAuth
    private let base = "https://api.spotify.com/v1"

    init(auth: SpotifyAuth) { self.auth = auth }

    // MARK: - Read

    func fetchNowPlaying() async -> NowPlaying? {
        // 204 No Content means nothing is playing.
        guard let data = await send("GET", "/me/player"), !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let item = json["item"] as? [String: Any]
        let artists = item?["artists"] as? [[String: Any]] ?? []
        let album = item?["album"] as? [String: Any]
        let images = album?["images"] as? [[String: Any]] ?? []
        let device = json["device"] as? [String: Any]

        return NowPlaying(
            title: item?["name"] as? String ?? "Untitled",
            artist: artists.compactMap { $0["name"] as? String }.joined(separator: ", "),
            isPlaying: json["is_playing"] as? Bool ?? false,
            trackURI: item?["uri"] as? String,
            artworkURL: images.first?["url"] as? String,
            progressMs: json["progress_ms"] as? Int ?? 0,
            durationMs: item?["duration_ms"] as? Int ?? 0,
            volume: device?["volume_percent"] as? Int ?? 50,
            volumeSupported: device?["supports_volume"] as? Bool ?? false,
            deviceName: device?["name"] as? String
        )
    }

    // MARK: - Playback control

    func play() async { _ = await send("PUT", "/me/player/play") }
    func pause() async { _ = await send("PUT", "/me/player/pause") }
    func next() async { _ = await send("POST", "/me/player/next") }
    func previous() async { _ = await send("POST", "/me/player/previous") }

    func seek(to ms: Int) async {
        _ = await send("PUT", "/me/player/seek",
                       query: [URLQueryItem(name: "position_ms", value: "\(max(ms, 0))")])
    }

    /// Returns false when the device refuses remote volume control.
    /// `supports_volume` is not always accurate, so the caller should also
    /// react to a failure here.
    func setVolume(_ percent: Int) async -> Bool {
        let clamped = min(max(percent, 0), 100)
        return await sendChecked("PUT", "/me/player/volume",
                                 query: [URLQueryItem(name: "volume_percent", value: "\(clamped)")])
    }

    // MARK: - Library

    /// Saves the current track.
    ///
    /// The February 2026 API update consolidated the library endpoints into
    /// `PUT /me/library`, which takes Spotify URIs via the `uris` query
    /// parameter. Older builds used `PUT /me/tracks?ids=`. If the new endpoint
    /// returns 404 on your account, flip `useLegacyEndpoint` to true.
    func saveToLibrary(uri: String) async -> Bool {
        let useLegacyEndpoint = false

        if useLegacyEndpoint {
            let id = uri.replacingOccurrences(of: "spotify:track:", with: "")
            return await sendChecked("PUT", "/me/tracks",
                                     query: [URLQueryItem(name: "ids", value: id)])
        } else {
            return await sendChecked("PUT", "/me/library",
                                     query: [URLQueryItem(name: "uris", value: uri)])
        }
    }

    // MARK: - Request plumbing

    @discardableResult
    private func send(_ method: String,
                      _ path: String,
                      query: [URLQueryItem]? = nil,
                      body: Data? = nil) async -> Data? {
        guard let request = await makeRequest(method, path, query: query, body: body) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("[API] \(http.statusCode) \(method) \(path):",
                      String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch {
            print("[API] Network error on \(path):", error)
            return nil
        }
    }

    /// Same as `send`, but reports whether the request actually succeeded.
    private func sendChecked(_ method: String,
                             _ path: String,
                             query: [URLQueryItem]? = nil,
                             body: Data? = nil) async -> Bool {
        guard let request = await makeRequest(method, path, query: query, body: body) else {
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if http.statusCode >= 400 {
                print("[API] \(http.statusCode) \(method) \(path):",
                      String(data: data, encoding: .utf8) ?? "")
                return false
            }
            return true
        } catch {
            print("[API] Network error on \(path):", error)
            return false
        }
    }

    private func makeRequest(_ method: String,
                             _ path: String,
                             query: [URLQueryItem]?,
                             body: Data?) async -> URLRequest? {
        guard let token = await auth.validToken() else {
            print("[API] No valid token for \(path)")
            return nil
        }

        // URLComponents handles percent-encoding of Spotify URIs correctly.
        guard var comps = URLComponents(string: base + path) else { return nil }
        if let query, !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
