import Foundation

enum Config {
    // Paste your client ID
    static let clientID = "YOUR_CLIENT_ID_HERE"

    // Paste your URL
    static let redirectURI = "com.yourname.spotifyremote://callback"

    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-library-modify",
        "user-follow-modify"
    ].joined(separator: " ")
}
