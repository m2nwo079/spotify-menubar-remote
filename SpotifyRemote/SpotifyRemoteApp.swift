import SwiftUI
import AppKit
import Combine

// MARK

@main
struct SpotifyRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = RemoteModel()

    var body: some Scene {
        MenuBarExtra {
            RemoteView().environmentObject(model)
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onURL: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { AppDelegate.onURL?($0) }
    }
}

// MARK

@MainActor
final class RemoteModel: ObservableObject {
    @Published var auth = SpotifyAuth()
    @Published var nowPlaying: NowPlaying?
    @Published var devices: [PlaybackDevice] = []
    @Published var savedMessage: String?

    private var api: SpotifyAPI!
    private var timer: Timer?
    private var localTimer: Timer?
    
    
    init() {
        api = SpotifyAPI(auth: auth)

        AppDelegate.onURL = { [weak self] url in
            Task { @MainActor in
                await self?.auth.handleCallback(url)
                await self?.refresh()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
        
        localTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, var now = self.nowPlaying, now.isPlaying else { return }
                now.progressMs = min(now.progressMs + 500, now.durationMs)
                self.nowPlaying = now
            }
        }
        
    }

    func refresh() async {
        guard auth.isLoggedIn else { return }
        nowPlaying = await api.fetchNowPlaying()
        devices = await api.fetchDevices()
    }

    func togglePlay() async {
        guard let now = nowPlaying else { return }
        now.isPlaying ? await api.pause() : await api.play()
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
    }

    func next() async {
        await api.next()
        try? await Task.sleep(for: .milliseconds(600))
        await refresh()
    }

    func previous() async {
        await api.previous()
        try? await Task.sleep(for: .milliseconds(600))
        await refresh()
    }

    func transfer(to device: PlaybackDevice) async {
        await api.transfer(to: device.id)
        try? await Task.sleep(for: .milliseconds(800))
        await refresh()
    }

    func saveCurrent() async {
            guard let uri = nowPlaying?.trackURI else { return }
            await api.saveToLibrary(uri: uri)
            savedMessage = "라이브러리에 저장했습니다"
            try? await Task.sleep(for: .seconds(2))
            savedMessage = nil
        }

        func setVolume(_ percent: Int) async {
            await api.setVolume(percent)
        }

        func seek(to ms: Int) async {
            await api.seek(to: ms)
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }


// MARK

struct RemoteView: View {
    @EnvironmentObject var model: RemoteModel
    @State private var volume: Double = 50
    @State private var isDraggingVolume = false
    @State private var seekPosition: Double = 0
    @State private var isDraggingSeek = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.auth.isLoggedIn {
                Text("Login Spotify").font(.callout)
                Button("Login") { model.auth.startLogin() }
            } else {
                nowPlayingSection
                progressSection
                controlSection
                volumeSection
                Divider()
                deviceSection
                Divider()
                Button("Logout") { model.auth.logout() }
                    .buttonStyle(.plain).font(.caption)
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

    private var nowPlayingSection: some View {
        HStack(spacing: 10) {
            if let urlString = model.nowPlaying?.artworkURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "music.note")
                        .foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 2) {
                if let now = model.nowPlaying {
                    Text(now.title).font(.headline).lineLimit(1)
                    Text(now.artist).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Empty")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let message = model.savedMessage {
                    Text(message).font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
        }
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
        }
        .buttonStyle(.borderless)
    }

    private var volumeSection: some View {
        HStack(spacing: 8) {
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
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("재생 기기").font(.caption).foregroundStyle(.secondary)
            ForEach(model.devices) { device in
                Button {
                    Task { await model.transfer(to: device) }
                } label: {
                    HStack {
                        Image(systemName: device.isActive
                              ? "largecircle.fill.circle" : "circle")
                        Text(device.name).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            if model.devices.isEmpty {
                Text("No Usable Device")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func timeText(_ ms: Int) -> String {
        let total = ms / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
