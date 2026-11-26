import AppKit
import Observation

/// What Music or Spotify is playing. Both apps announce track changes with a distributed
/// notification, so this costs nothing while idle and needs no private frameworks.
@Observable
final class NowPlaying {
    enum Player: String {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var notification: String { self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged" }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var player: Player
    }

    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var accent: NSColor?

    @ObservationIgnored private let scriptQueue = DispatchQueue(label: "brim.applescript")

    var hasTrack: Bool { track != nil }

    func start() {
        let center = DistributedNotificationCenter.default()
        for player in [Player.music, .spotify] {
            center.addObserver(forName: Notification.Name(player.notification), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let state = info["Player State"] as? String ?? ""
                let title = info["Name"] as? String
                let artist = info["Artist"] as? String ?? ""
                let album = info["Album"] as? String ?? ""
                MainActor.assumeIsolated {
                    self?.received(player: player, state: state, title: title, artist: artist, album: album)
                }
            }
        }
    }

    private func received(player: Player, state: String, title: String?, artist: String, album: String) {
        if state == "Stopped" || title == nil {
            if track?.player == player { track = nil; isPlaying = false; artwork = nil; accent = nil }
            return
        }
        let next = Track(title: title ?? "", artist: artist, album: album, player: player)
        let changed = next != track
        track = next
        isPlaying = state == "Playing"
        if changed { loadArtwork(for: next) }
    }

    // MARK: Controls

    func togglePlayPause() { send("playpause"); isPlaying.toggle() }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func openPlayer() {
        guard let player = track?.player,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: String) {
        guard let player = track?.player else { return }
        run("tell application \"\(player.rawValue)\" to \(command)")
    }

    // MARK: Artwork

    private func loadArtwork(for track: Track) {
        switch track.player {
        case .spotify:
            run("tell application \"Spotify\" to artwork url of current track") { [weak self] result in
                guard let string = result?.stringValue, let url = URL(string: string) else { return }
                Task { @MainActor in
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                    self?.setArtwork(NSImage(data: data), for: track)
                }
            }
        case .music:
            run("tell application \"Music\" to get data of artwork 1 of current track") { [weak self] result in
                let image = result.flatMap { NSImage(data: $0.data) }
                Task { @MainActor in self?.setArtwork(image, for: track) }
            }
        }
    }

    private func setArtwork(_ image: NSImage?, for track: Track) {
        guard self.track == track else { return }
        artwork = image
        accent = image?.dominantColor
    }

    private func run(_ source: String, completion: (@Sendable (NSAppleEventDescriptor?) -> Void)? = nil) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            completion?(error == nil ? result : nil)
        }
    }
}

extension NSImage {
    /// The average of a tiny thumbnail, lifted so it reads on black.
    var dominantColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        var r = 0, g = 0, b = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2])
        }
        let count = CGFloat(size * size * 255)
        let color = NSColor(srgbRed: CGFloat(r) / count, green: CGFloat(g) / count, blue: CGFloat(b) / count, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return NSColor(hue: hue, saturation: min(saturation * 1.2, 0.85), brightness: max(brightness, 0.75), alpha: 1)
    }
}

extension NowPlaying {
    func loadDemo(title: String, artist: String, album: String, artwork: NSImage) {
        track = Track(title: title, artist: artist, album: album, player: .music)
        isPlaying = true
        self.artwork = artwork
        accent = artwork.dominantColor
    }
}
