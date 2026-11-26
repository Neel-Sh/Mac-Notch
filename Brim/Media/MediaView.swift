import SwiftUI

struct MediaPage: View {
    let player: NowPlaying

    var body: some View {
        if let track = player.track {
            HStack(spacing: 16) {
                Artwork(image: player.artwork, size: 84)
                    .onTapGesture { player.openPlayer() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(Theme.title(15))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Text(track.album)
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 12) {
                        Button(action: player.previous) { Image(systemName: "backward.fill") }
                            .buttonStyle(IconButtonStyle(size: 30))
                        Button(action: player.togglePlayPause) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(IconButtonStyle(size: 36))
                        Button(action: player.next) { Image(systemName: "forward.fill") }
                            .buttonStyle(IconButtonStyle(size: 30))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                Text("Nothing playing")
                    .font(Theme.title(13))
                    .foregroundStyle(Theme.secondary)
                Text("Play something in Music or Spotify.")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Artwork: View {
    let image: NSImage?
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
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
