import SwiftUI

struct ShelfPage: View {
    let shelf: ShelfStore
    let isDropTargeted: Bool
    @Environment(\.islandStyle) private var style

    /// A file dragged over the island always lands on the shelf, whichever half is showing.
    private var showsRecents: Bool { shelf.showsRecents && !isDropTargeted }

    var body: some View {
        if shelf.items.isEmpty && shelf.history.isEmpty {
            DropHint(active: isDropTargeted)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header
                Group {
                    if showsRecents {
                        RecentsList(shelf: shelf)
                    } else if shelf.items.isEmpty {
                        DropHint(active: isDropTargeted, compact: true)
                    } else if style.edge.isSide {
                        shelfGrid
                    } else {
                        shelfContent
                    }
                }
                .transition(.opacity.animation(Motion.swap))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SegmentPill(title: "Shelf", count: shelf.items.count, selected: !showsRecents) {
                withAnimation(Motion.swap) { shelf.showsRecents = false }
            }
            SegmentPill(title: "Recents", count: shelf.history.count, selected: showsRecents) {
                withAnimation(Motion.swap) { shelf.showsRecents = true }
            }
            if let message = shelf.lastMessage {
                Text(message)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.done)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
            Spacer()
            if showsRecents {
                if shelf.history.contains(where: { !shelf.isOnShelf($0) }) {
                    Button(style.edge.isSide ? "Clear" : "Clear Recents") { withAnimation(Motion.swap) { shelf.clearHistory() } }
                        .buttonStyle(PillButtonStyle(kind: .quiet))
                        .help("Forget past files. Nothing is deleted from disk.")
                }
            } else if !shelf.items.isEmpty {
                Button("Clear") { withAnimation(Motion.swap) { shelf.clear() } }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .help("Empty the shelf. The files stay in Recents.")
            }
        }
        .frame(height: 28)
        .animation(Motion.swap, value: shelf.lastMessage)
    }

    /// Docked: the files as a grid that scrolls, the actions held at the foot.
    private var shelfGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                    ForEach(shelf.items) { item in
                        FileTile(item: item, thumbnail: shelf.thumbnail(for: item), fills: true) {
                            withAnimation(Motion.swap) { shelf.remove(item.id) }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if isDropTargeted { DropSlot().transition(.opacity) }
                }
                .animation(Motion.swap, value: shelf.items)
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .frame(maxHeight: .infinity)
            actions
        }
    }

    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(shelf.items) { item in
                        FileTile(item: item, thumbnail: shelf.thumbnail(for: item)) {
                            withAnimation(Motion.swap) { shelf.remove(item.id) }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if isDropTargeted { DropSlot().transition(.opacity) }
                }
                .animation(Motion.swap, value: shelf.items)
            }
            .scrollIndicators(.never)
            actions
        }
    }

    private var actions: some View {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ActionRow(symbol: "airplayaudio", title: "AirDrop", action: shelf.airDrop)
                    ActionRow(symbol: "doc.on.doc", title: "Copy", action: shelf.copy)
                }
                GridRow {
                    if shelf.canMakePDF {
                        ActionRow(symbol: "doc.richtext", title: "Make PDF", action: shelf.makePDF)
                        // Docked, half the panel is too narrow for the long name.
                        ActionRow(symbol: "folder", title: style.edge.isSide ? "Reveal" : "Show in Finder",
                                  action: shelf.revealInFinder)
                            .help("Show in Finder")
                    } else {
                        ActionRow(symbol: "folder", title: "Show in Finder", action: shelf.revealInFinder)
                            .gridCellColumns(2)
                    }
                }
            }
    }
}

/// One half of the Shelf page's switch: a label and how many files it holds.
private struct SegmentPill: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(selected ? Theme.secondary : Theme.tertiary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .foregroundStyle(selected ? Theme.primary : Theme.secondary)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.13 : (hovered ? 0.06 : 0))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .animation(Motion.swap, value: count)
    }
}

/// The last files that passed through the shelf, newest first. Click one to put it back,
/// drag it straight out, or swipe left (two fingers) to forget it.
private struct RecentsList: View {
    let shelf: ShelfStore

    var body: some View {
        if shelf.history.isEmpty {
            Text("Files you drop on the shelf show up here, so you can find them again.")
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SwipeList(items: shelf.history, rowHeight: ShelfPage.recentRowHeight,
                      actionTitle: "Remove from Recents", actionSymbol: "xmark") { item in
                RecentRow(item: item, thumbnail: shelf.thumbnail(for: item), onShelf: shelf.isOnShelf(item),
                          restore: { withAnimation(Motion.swap) { shelf.restore(item) } },
                          forget: { withAnimation(Motion.swap) { shelf.forget(item.id) } })
            } onSwipe: { item in
                shelf.forget(item.id)
            }
        }
    }
}

private struct RecentRow: View {
    let item: ShelfItem
    let thumbnail: NSImage?
    let onShelf: Bool
    let restore: () -> Void
    let forget: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(item.url.deletingLastPathComponent().lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(item.addedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .fixedSize()
                }
                .font(Theme.body(10.5))
                .foregroundStyle(Theme.tertiary)
            }

            Spacer(minLength: 8)

            if hovered {
                HStack(spacing: 6) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(IconButtonStyle(size: 26))
                    .help("Show in Finder")
                    Button(action: forget) { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(size: 26))
                        .help("Remove from Recents (the file stays on disk)")
                }
                .transition(.opacity)
            }

            if onShelf {
                Label("On shelf", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            } else {
                Button("Add", systemImage: "tray.and.arrow.down", action: restore)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .help("Put it back on the shelf")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
    }
}

extension ShelfPage {
    static let recentRowHeight: CGFloat = 42
    /// How many Recents rows show before the list scrolls.
    static let visibleRecents = 5
}

private struct DropHint: View {
    let active: Bool
    var compact = false
    @Environment(\.islandStyle) private var style

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: active ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(active ? Theme.primary : Theme.tertiary)
                .symbolEffect(.bounce, value: active)
            Text(active ? "Drop to keep it here" : (style.edge.isSide ? "Drag files onto Brim" : "Drag files onto the notch"))
                .font(Theme.title(12.5))
                .foregroundStyle(active ? Theme.primary : Theme.secondary)
            if !compact {
                Text("They wait here until you know where they go. Drag them back out any time.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
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
    /// Stretch to the grid cell instead of holding the strip's fixed width.
    var fills = false
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
        .frame(maxWidth: fills ? .infinity : nil)
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
                    .lineLimit(1)
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
