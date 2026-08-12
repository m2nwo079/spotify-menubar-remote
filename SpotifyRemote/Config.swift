import Foundation

enum Config {
    // Paste your Client ID from the Spotify Developer Dashboard
    static let clientID = "YOUR_CLIENT_ID_HERE"

    // Must exactly match the Redirect URI registered in the Dashboard
    // and the URL Scheme registered in Xcode (Info > URL Types)
    static let redirectURI = "com.yourname.spotifyremote://callback"

    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-library-modify",
        "user-follow-modify"
    ].joined(separator: " ")
}
