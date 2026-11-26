import SwiftUI

struct ShelfPage: View {
    let shelf: ShelfStore
    let isDropTargeted: Bool

    var body: some View {
        if shelf.items.isEmpty {
            DropHint(active: isDropTargeted)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")")
                        .font(Theme.title(12.5))
                    if let message = shelf.lastMessage {
                        Text(message)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.done)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button("Clear") { withAnimation(Motion.swap) { shelf.clear() } }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .animation(Motion.swap, value: shelf.lastMessage)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items) { item in
                            FileTile(item: item, thumbnail: shelf.thumbnails[item.id]) {
                                withAnimation(Motion.swap) { shelf.remove(item.id) }
                            }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        if isDropTargeted { DropSlot().transition(.opacity) }
                    }
                    .animation(Motion.swap, value: shelf.items)
                }
                .scrollIndicators(.never)

                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        ActionRow(symbol: "airplayaudio", title: "AirDrop", action: shelf.airDrop)
                        ActionRow(symbol: "doc.on.doc", title: "Copy", action: shelf.copy)
                    }
                    GridRow {
                        if shelf.canMakePDF {
                            ActionRow(symbol: "doc.richtext", title: "Make PDF", action: shelf.makePDF)
                            ActionRow(symbol: "folder", title: "Show in Finder", action: shelf.revealInFinder)
                        } else {
                            ActionRow(symbol: "folder", title: "Show in Finder", action: shelf.revealInFinder)
                                .gridCellColumns(2)
                        }
                    }
                }
            }
        }
    }
}

private struct DropHint: View {
    let active: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: active ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(active ? Theme.primary : Theme.tertiary)
                .symbolEffect(.bounce, value: active)
            Text(active ? "Drop to keep it here" : "Drag files onto the notch")
                .font(Theme.title(12.5))
                .foregroundStyle(active ? Theme.primary : Theme.secondary)
            Text("They wait here until you know where they go. Drag them back out any time.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(active ? 0.35 : 0.1), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .animation(Motion.swap, value: active)
    }
}

private struct DropSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            .frame(width: 72, height: 72)
            .overlay(Image(systemName: "plus").foregroundStyle(Theme.secondary))
    }
}

private struct FileTile: View {
    let item: ShelfItem
    let thumbnail: NSImage?
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc").font(.system(size: 22)).foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(width: 52, height: 52)
                .frame(width: 72, height: 58)

                if hovered {
                    Button(action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .heavy))
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color(white: 0.3)))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovered ? 0.08 : 0.04)))
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
    }
}

private struct ActionRow: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(Theme.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovered ? 0.1 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
    }
}
