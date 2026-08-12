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
}

struct PlaybackDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isActive: Bool
}

@MainActor
final class SpotifyAPI {
    private let auth: SpotifyAuth
    private let base = "https://api.spotify.com/v1"

    init(auth: SpotifyAuth) { self.auth = auth }

    // MARK

    func fetchNowPlaying() async -> NowPlaying? {
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
            volume: device?["volume_percent"] as? Int ?? 50
        )
    }

    func fetchDevices() async -> [PlaybackDevice] {
        guard let data = await send("GET", "/me/player/devices"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["devices"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { d in
            guard let id = d["id"] as? String,
                  let name = d["name"] as? String else { return nil }
            return PlaybackDevice(id: id, name: name,
                                  isActive: d["is_active"] as? Bool ?? false)
        }
    }

    // MARK

    func play() async { _ = await send("PUT", "/me/player/play") }
    func pause() async { _ = await send("PUT", "/me/player/pause") }
    func next() async { _ = await send("POST", "/me/player/next") }
    func previous() async { _ = await send("POST", "/me/player/previous") }
    func setVolume(_ percent: Int) async {
        _ = await send("PUT", "/me/player/volume?volume_percent=\(percent)")
    }

    func seek(to ms: Int) async {
        _ = await send("PUT", "/me/player/seek?position_ms=\(ms)")
    }

    func transfer(to deviceID: String) async {
        let body = try? JSONSerialization.data(
            withJSONObject: ["device_ids": [deviceID], "play": true]
        )
        _ = await send("PUT", "/me/player", body: body)
    }

    func saveToLibrary(uri: String) async {
        let encoded = uri.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? uri
        _ = await send("PUT", "/me/library?uris=\(encoded)")
    }

    // MARK

    @discardableResult
    private func send(_ method: String, _ path: String,
                     body: Data? = nil) async -> Data? {
        guard let token = await auth.validToken(),
              let url = URL(string: base + path) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("Error \(http.statusCode) — \(path):",
                      String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch {
            print("Network Error:", error)
            return nil
        }
    }
}
