import AppKit
import Combine
import SwiftUI

// MARK: - App entry point

@main
struct SpotifyRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = RemoteModel()

    var body: some Scene {
        MenuBarExtra {
            RemoteView().environmentObject(model)
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Receives the OAuth redirect from the browser

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var onURL: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { AppDelegate.onURL?($0) }
    }
}

// MARK: - State

@MainActor
final class RemoteModel: ObservableObject {
    @Published var auth = SpotifyAuth()
    @Published var nowPlaying: NowPlaying?
    @Published var statusMessage: String?

    /// Set once a device rejects remote volume control, so the slider stops
    /// firing requests that will only fail again.
    @Published var volumeBlocked = false

    /// Tick interval for the local progress estimate, in seconds.
    private let tickInterval: TimeInterval = 0.25

    private var api: SpotifyAPI!
    private var pollTimer: Timer?
    private var tickTimer: Timer?

    /// Blocks polling while a command is in flight, so the UI does not
    /// briefly revert to stale server state.
    private var isBusy = false

    init() {
        api = SpotifyAPI(auth: auth)

        AppDelegate.onURL = { [weak self] url in
            Task { @MainActor in
                await self?.auth.handleCallback(url)
                await self?.refresh()
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        // Advances the progress bar between server updates. Costs no API calls.
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, var now = self.nowPlaying, now.isPlaying else { return }
                now.progressMs = min(now.progressMs + Int(self.tickInterval * 1000),
                                     now.durationMs)
                self.nowPlaying = now
            }
        }

        Task { await refresh() }
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
    }

    // MARK: Polling

    func refresh() async {
        guard auth.isLoggedIn, !isBusy else { return }

        let fetched = await api.fetchNowPlaying()

        // Reset the volume lock when playback moves to a different device.
        if fetched?.deviceName != nowPlaying?.deviceName {
            volumeBlocked = false
        }

        // Keep the locally estimated position when the server agrees closely,
        // so the progress bar does not jump backwards every few seconds.
        if var new = fetched,
           let old = nowPlaying,
           new.trackURI == old.trackURI,
           abs(new.progressMs - old.progressMs) < 1500 {
            new.progressMs = old.progressMs
            nowPlaying = new
        } else {
            nowPlaying = fetched
        }
    }

    // MARK: Commands

    func togglePlay() async {
        guard let now = nowPlaying else { return }
        await run(delay: 400) {
            now.isPlaying ? await self.api.pause() : await self.api.play()
        }
    }

    func next() async {
        await run(delay: 600) { await self.api.next() }
    }

    func previous() async {
        await run(delay: 600) { await self.api.previous() }
    }

    func seek(to ms: Int) async {
        await run(delay: 400) { await self.api.seek(to: ms) }
    }

    func setVolume(_ percent: Int) async {
        guard !volumeBlocked else { return }
        let ok = await api.setVolume(percent)
        if !ok {
            volumeBlocked = true
            await show("This device does not allow volume control")
        }
    }

    func saveCurrent() async {
        guard let uri = nowPlaying?.trackURI else { return }
        let ok = await api.saveToLibrary(uri: uri)
        await show(ok ? "Saved to library" : "Could not save")
    }

    // MARK: Helpers

    /// Runs a command, suppressing polling until the server catches up.
    private func run(delay ms: Int, _ command: () async -> Void) async {
        isBusy = true
        await command()
        try? await Task.sleep(for: .milliseconds(ms))
        isBusy = false
        await refresh()
    }

    private func show(_ message: String) async {
        statusMessage = message
        try? await Task.sleep(for: .seconds(2))
        if statusMessage == message { statusMessage = nil }
    }
}

// MARK: - Menu bar popover

struct RemoteView: View {
    @EnvironmentObject var model: RemoteModel

    @State private var volume: Double = 50
    @State private var isDraggingVolume = false
    @State private var seekPosition: Double = 0
    @State private var isDraggingSeek = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.auth.isLoggedIn {
                loginSection
            } else {
                nowPlayingSection
                progressSection
                controlSection
                volumeSection
                Divider()
                footerSection
            }
        }
        .padding(14)
        .frame(width: 280)
        .onChange(of: model.nowPlaying?.volume) { _, new in
            if let new, !isDraggingVolume { volume = Double(new) }
        }
        .onChange(of: model.nowPlaying?.progressMs) { _, new in
            if let new, !isDraggingSeek { seekPosition = Double(new) }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to Spotify").font(.callout)
            Button("Log in") { model.auth.startLogin() }
        }
    }

    private var nowPlayingSection: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                if let now = model.nowPlaying {
                    Text(now.title).font(.headline).lineLimit(1)
                    Text(now.artist).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Nothing playing")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let message = model.statusMessage {
                    Text(message).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
        // Opens the current track in Spotify.
        .contentShape(Rectangle())
        .onTapGesture { openCurrentTrack() }
        .help(model.nowPlaying == nil ? "" : "Open in Spotify")
    }

    private func openCurrentTrack() {
        guard let uri = model.nowPlaying?.trackURI else { return }

        if let url = URL(string: uri), NSWorkspace.shared.open(url) { return }

        // Fall back to the web player.
        let id = uri.replacingOccurrences(of: "spotify:track:", with: "")
        if let web = URL(string: "https://open.spotify.com/track/\(id)") {
            NSWorkspace.shared.open(web)
        }
    }

    private var artwork: some View {
        Group {
            if let urlString = model.nowPlaying?.artworkURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    .overlay(Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.secondary))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var progressSection: some View {
        VStack(spacing: 2) {
            Slider(
                value: $seekPosition,
                in: 0...max(Double(model.nowPlaying?.durationMs ?? 1), 1),
                onEditingChanged: { editing in
                    isDraggingSeek = editing
                    if !editing {
                        Task { await model.seek(to: Int(seekPosition)) }
                    }
                }
            )
            .controlSize(.mini)
            .animation(isDraggingSeek ? nil : .linear(duration: 0.25), value: seekPosition)
            .disabled(model.nowPlaying == nil)

            HStack {
                Text(timeText(Int(seekPosition)))
                Spacer()
                Text(timeText(model.nowPlaying?.durationMs ?? 0))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var controlSection: some View {
        HStack(spacing: 18) {
            Button { Task { await model.previous() } }
                label: { Image(systemName: "backward.fill") }
            Button { Task { await model.togglePlay() } }
                label: {
                    Image(systemName: model.nowPlaying?.isPlaying == true
                          ? "pause.fill" : "play.fill")
                }
            Button { Task { await model.next() } }
                label: { Image(systemName: "forward.fill") }
            Spacer()
            Button { Task { await model.saveCurrent() } }
                label: { Image(systemName: "heart") }
                .disabled(model.nowPlaying == nil)
        }
        .buttonStyle(.borderless)
    }

    private var volumeSection: some View {
        let available = (model.nowPlaying?.volumeSupported ?? false) && !model.volumeBlocked

        return HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: $volume, in: 0...100,
                   onEditingChanged: { editing in
                       isDraggingVolume = editing
                       if !editing {
                           Task { await model.setVolume(Int(volume)) }
                       }
                   })
            .controlSize(.mini)
            .disabled(!available)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .opacity(available ? 1 : 0.35)
        .help(available ? "" : "This device does not allow remote volume control")
    }

    /// Shows where playback is happening. Switching devices is done in the
    /// Spotify app itself — the Web API transfer endpoint is unreliable.
    private var footerSection: some View {
        HStack {
            if let name = model.nowPlaying?.deviceName {
                Image(systemName: "wave.3.right")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(name).font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Log out") { model.auth.logout() }
                .buttonStyle(.plain)
                .font(.caption)
        }
    }

    private func timeText(_ ms: Int) -> String {
        let total = max(ms, 0) / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
