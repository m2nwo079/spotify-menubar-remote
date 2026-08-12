# Spotify Menu Bar Remote

A lightweight macOS menu bar app to control Spotify playback.

Built with SwiftUI. No dock icon, no window — it lives in your menu bar.

## Features

- Now playing info with album artwork
- Play / pause, next, previous
- Seek bar with drag-to-scrub and smooth local interpolation
- Volume slider, automatically disabled on devices that reject remote control
- Save the current track to your library with one click
- Click the artwork or title to open the current track in Spotify
- Click the device name to bring the Spotify app forward
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

Press ▶︎. An icon appears in your menu bar. Click it and sign in.

To install it permanently: **Product → Archive → Distribute App → Custom → Copy App**, then move the result to `/Applications`.

## Notes

**This app does not play audio.** The Spotify Web API is a remote control — it commands playback that is already running on one of your devices. If nothing shows up, start playing something in the Spotify app first.

**No device switching.** Transferring playback via `PUT /me/player` fails unpredictably against idle devices, returning 404 or 500 and sometimes dropping the target device from the device list entirely. This has been reported since 2018 and is not fixable from the client side, so the feature was removed. The app shows which device is playing and opens Spotify when you click it — switch there instead.

**Volume control is device-dependent.** Some devices return `VOLUME_CONTROL_DISALLOW`. The app reads `supports_volume` and also locks the slider after any rejection, unlocking it when playback moves elsewhere.

**Only 5 users, ever.** Spotify Development Mode caps apps at five allowlisted users, and [extended quota mode](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) is restricted to registered organizations with 250,000+ monthly active users. This app cannot be distributed as a binary. Clone it and use your own Client ID.

**Polling, not push.** The Web API has no realtime channel, so state is polled every 3 seconds. The progress bar is interpolated locally between polls at no extra API cost.

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
