# Spotify Menu Bar Remote

A lightweight macOS menu bar app to control Spotify playback across your devices.

Built with SwiftUI. No dock icon, no window — it lives in your menu bar.

## Features

- Now playing info with album artwork
- Play / pause, next, previous
- Seek bar with drag-to-scrub
- Volume slider
- **Device switching** — move playback between your Mac, phone, or speakers
- Save the current track to your library with one click
- Auto-refresh every 3 seconds, with smooth local progress interpolation
- Login persists via macOS Keychain

## Requirements

- macOS 13.0 or later
- **Spotify Premium** — required both by the Web API playback endpoints and by Spotify's Development Mode policy
- Xcode 15 or later
- A Spotify Developer app (free)

## Setup

### 1. Create a Spotify app

Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and create an app.

Under **Settings → Redirect URIs**, add a custom URL scheme. Pick your own reverse-DNS identifier:

    com.yourname.spotifyremote://callback

Note that `http://localhost` is no longer accepted. Spotify only allows HTTPS URLs, loopback IP literals such as `http://127.0.0.1:PORT`, or custom schemes like the one above.

Copy your **Client ID**. You do not need the Client Secret — this app uses PKCE.

### 2. Configure the project

Open `SpotifyRemote/Config.swift` and fill in both values:

```swift
static let clientID = "your_client_id"
static let redirectURI = "com.yourname.spotifyremote://callback"
```

### 3. Register the URL scheme in Xcode

Select the **SpotifyRemote** target → **Info** tab → **URL Types** → **+**

- **Identifier**: `com.yourname.spotifyremote`
- **URL Schemes**: `com.yourname.spotifyremote`

This must match the redirect URI from step 1, minus the `://callback` part. It is case-sensitive.

### 4. Enable network access

Target → **Signing & Capabilities** → **App Sandbox** → check **Outgoing Connections (Client)**.

Without this the app fails silently with no error message.

### 5. Build and run

Press ▶︎. A music note icon appears in your menu bar. Click it and sign in.

To install it permanently: **Product → Archive → Distribute App → Custom → Copy App**, then move the result to `/Applications`.

## Notes

**This app does not play audio.** The Spotify Web API is a remote control — it commands playback that is already running on one of your devices. If nothing shows up, start playing something in the Spotify app first.

**Only 5 users, ever.** Spotify Development Mode caps apps at five allowlisted users, and [extended quota mode](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) is restricted to registered organizations with 250,000+ monthly active users. This app cannot be distributed as a binary. Clone it and use your own Client ID.

**Some devices reject volume changes.** Certain Spotify Connect speakers do not support the volume endpoint and will return an error. Mac and iPhone work fine.

## What this app cannot do

The following were removed from the Spotify Web API in November 2024 and February 2026, and are unavailable to any new app:

- Recommendations
- Audio features and audio analysis (tempo, energy, danceability)
- 30-second preview URLs
- Track popularity
- Bulk metadata fetches
- Artist top tracks, new releases, browse categories

## License

MIT
