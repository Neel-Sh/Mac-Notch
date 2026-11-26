import SwiftUI

struct MediaPage: View {
    let player: NowPlaying
    @Environment(\.islandStyle) private var style

    var body: some View {
        if let track = player.track {
            let tint = Color(nsColor: player.accent ?? .white)
            Group {
                if style.edge.isSide {
                    portrait(track, tint: tint)
                } else {
                    landscape(track, tint: tint)
                }
            }
            .onAppear(perform: player.refreshPosition)
        } else {
            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.bottom, 2)
                    Text("Nothing playing")
                        .font(Theme.title(13))
                        .foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(NowPlaying.Player.installed, id: \.self) { app in
                        Button("Open \(app.rawValue)") { app.launch() }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// On the notch: the cover on the left, everything else beside it.
    private func landscape(_ track: NowPlaying.Track, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 18) {
            cover(track, tint: tint, size: MediaPage.artworkSize)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    titles(track, size: 16)
                    Spacer(minLength: 0)
                    SourceChip(name: track.player.rawValue, playing: player.isPlaying, tint: tint,
                               action: player.openPlayer)
                }

                Spacer(minLength: 8)
                Scrubber(player: player, tint: tint)
                Spacer(minLength: 8)
                transport(side: 32, play: 38)
            }
            .frame(height: MediaPage.artworkSize)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Docked: the cover takes the panel, the track sits under it, the transport at the foot.
    private func portrait(_ track: NowPlaying.Track, tint: Color) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            cover(track, tint: tint, size: MediaPage.portraitArtwork(compact: style.compact), radius: 30)
            Spacer(minLength: 14)
            HStack(alignment: .center, spacing: 10) {
                titles(track, size: 17)
                Spacer(minLength: 0)
                SourceChip(name: track.player.rawValue, playing: player.isPlaying, tint: tint,
                           action: player.openPlayer)
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 10)
            Scrubber(player: player, tint: tint)
                .padding(.horizontal, 4)
            Spacer(minLength: 10)
            transport(side: 38, play: 48, spacing: 18)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cover(_ track: NowPlaying.Track, tint: Color, size: CGFloat, radius: CGFloat? = nil) -> some View {
        Button(action: player.openPlayer) {
            Artwork(image: player.artwork, size: size, radius: radius)
                .shadow(color: tint.opacity(player.artwork == nil ? 0 : 0.35), radius: 18, y: 6)
        }
        .buttonStyle(PressableStyle())
        .help("Open \(track.player.rawValue)")
    }

    private func titles(_ track: NowPlaying.Track, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
                .font(Theme.title(size))
                .foregroundStyle(Theme.primary)
            Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                .font(Theme.body(12))
                .foregroundStyle(Theme.secondary)
        }
        .lineLimit(1)
        .id(track)
        .transition(.opacity.animation(Motion.swap))
    }

    private func transport(side: CGFloat, play: CGFloat, spacing: CGFloat = 10) -> some View {
        HStack(spacing: spacing) {
            Button(action: player.previous) { Image(systemName: "backward.fill") }
                .buttonStyle(IconButtonStyle(size: side))
                .help("Previous")
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IconButtonStyle(size: play, prominent: true))
            .help(player.isPlaying ? "Pause" : "Play")
            .keyboardShortcut(.space, modifiers: [])
            Button(action: player.next) { Image(systemName: "forward.fill") }
                .buttonStyle(IconButtonStyle(size: side))
                .help("Next")
        }
    }

    static let artworkSize: CGFloat = 112
    static func portraitArtwork(compact: Bool) -> CGFloat { compact ? 168 : 216 }
}

/// Which app is playing, with the live equalizer. Opens the app.
private struct SourceChip: View {
    let name: String
    let playing: Bool
    let tint: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Equalizer(playing: playing, color: playing ? tint : Theme.tertiary)
                    .scaleEffect(0.8)
                    .frame(width: 14)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(hovered ? 0.11 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
    }
}

/// The playhead. Extrapolated locally between player reports; drag or click anywhere to seek.
private struct Scrubber: View {
    let player: NowPlaying
    let tint: Color
    @State private var dragFraction: Double?
    @State private var hovered = false

    var body: some View {
        let duration = player.duration
        TimelineView(.animation(minimumInterval: 0.5, paused: !player.isPlaying || dragFraction != nil)) { context in
            let elapsed = dragFraction.map { $0 * duration } ?? player.elapsed(at: context.date)
            let fraction = duration > 0 ? min(1, elapsed / duration) : 0
            HStack(spacing: 10) {
                Text(Self.clock(elapsed))
                    .frame(minWidth: 30, alignment: .leading)
                GeometryReader { geometry in
                    let active = hovered || dragFraction != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(active ? tint : Color.white.opacity(0.8))
                            .frame(width: max(active ? 6 : 4, geometry.size.width * fraction))
                    }
                    .frame(height: active ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                            }
                            .onEnded { _ in
                                if let dragFraction { player.seek(to: dragFraction * duration) }
                                dragFraction = nil
                            }
                    )
                    .animation(Motion.tap, value: active)
                }
                .frame(height: 14)
                .onHover { hovering in hovered = hovering }
                Text("-" + Self.clock(max(0, duration - elapsed)))
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiary)
        }
        .opacity(duration > 0 ? 1 : 0)
        .disabled(duration <= 0)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A soft wash of the album art behind the Music page, faded out under the notch.
struct ArtworkBackdrop: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .blur(radius: 50, opaque: true)
            .saturation(1.4)
            .opacity(0.32)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0.08), .init(color: .black, location: 0.6)],
                                 startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

struct Artwork: View {
    let image: NSImage?
    var size: CGFloat
    /// Defaults to a fifth of the size, which suits small covers; a big one names its own.
    var radius: CGFloat?

    var body: some View {
        let corner = radius ?? size * 0.2
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .animation(Motion.swap, value: image)
    }
}

/// Three bars that move only while music is actually playing.
struct Equalizer: View {
    let playing: Bool
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = t * (3.1 + Double(index) * 0.9) + Double(index) * 1.7
                    let level = playing ? 0.35 + 0.65 * abs(sin(phase)) : 0.25
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: 13 * level)
                }
            }
            .frame(height: 13)
        }
    }
}
