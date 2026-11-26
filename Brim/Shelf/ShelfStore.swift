import AppKit
import Observation
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let addedAt: Date

    var name: String { url.lastPathComponent }
    var isImage: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true }
}

/// Files dropped on the notch, waiting until you know where they go. Survives a restart.
/// Like a clipboard history, it also remembers the last few files that passed through,
/// so something cleared off the shelf can be found again.
@Observable
final class ShelfStore {
    /// How many past files Recents keeps.
    static let historyLimit = 10

    private(set) var items: [ShelfItem] = []
    /// Newest first. Includes what's on the shelf now; cleared or removed files stay here.
    private(set) var history: [ShelfItem] = []
    private(set) var thumbnails: [URL: NSImage] = [:]
    var lastMessage: String?
    /// Which half of the Shelf page is showing. Not saved: the page opens on the shelf.
    var showsRecents = false

    @ObservationIgnored private let storeURL = HookScript.directory.appendingPathComponent("shelf.json")
    @ObservationIgnored private let historyURL = HookScript.directory.appendingPathComponent("shelf-history.json")
    @ObservationIgnored private var isDemo = false

    init() {
        items = Self.load(from: storeURL)
        history = Self.load(from: historyURL)
        // Shelves saved before Recents existed still show up in it.
        for item in items.reversed() where !history.contains(where: { $0.url == item.url }) { history.insert(item, at: 0) }
        history = Array(history.prefix(Self.historyLimit))
        (items + history).forEach(loadThumbnail)
    }

    private static func load(from url: URL) -> [ShelfItem] {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return [] }
        return saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func thumbnail(for item: ShelfItem) -> NSImage? { thumbnails[item.url] }
    func isOnShelf(_ item: ShelfItem) -> Bool { items.contains { $0.url == item.url } }

    var urls: [URL] { items.map(\.url) }
    var canMakePDF: Bool { !items.isEmpty && items.allSatisfy(\.isImage) }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let fresh = urls.filter { !known.contains($0) }.map { ShelfItem(id: UUID(), url: $0, addedAt: .now) }
        items.append(contentsOf: fresh)
        fresh.forEach(loadThumbnail)
        remember(urls)
        save()
    }

    /// Takes a file off the shelf. It stays in Recents.
    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Empties the shelf. Everything on it stays in Recents.
    func clear() {
        items.removeAll()
        save()
    }

    // MARK: Recents

    /// Puts a past file back on the shelf, if it's still where it was.
    func restore(_ item: ShelfItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            forget(item.id)
            flash("\(item.name) has moved or been deleted")
            return
        }
        add([item.url])
    }

    /// Removes a file from Recents (and the shelf). The file itself is untouched.
    func forget(_ id: UUID) {
        guard let url = history.first(where: { $0.id == id })?.url else { return }
        history.removeAll { $0.id == id }
        items.removeAll { $0.url == url }
        thumbnails[url] = nil
        save()
    }

    /// Forgets every past file that isn't on the shelf right now.
    func clearHistory() {
        let kept = Set(items.map(\.url))
        history.removeAll { !kept.contains($0.url) }
        thumbnails = thumbnails.filter { kept.contains($0.key) }
        save()
    }

    /// Moves files to the top of Recents and trims it to the limit.
    private func remember(_ urls: [URL]) {
        for url in urls.reversed() {
            history.removeAll { $0.url == url }
            history.insert(ShelfItem(id: UUID(), url: url, addedAt: .now), at: 0)
        }
        let dropped = history.dropFirst(Self.historyLimit).map(\.url)
        history = Array(history.prefix(Self.historyLimit))
        let live = Set((items + history).map(\.url))
        for url in dropped where !live.contains(url) { thumbnails[url] = nil }
    }

    // MARK: Actions

    func airDrop() {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
        flash("Copied \(items.count == 1 ? items[0].name : "\(items.count) files")")
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Every image on the shelf, one per page, in one PDF next to the first image.
    func makePDF() {
        guard canMakePDF, let first = items.first else { return }
        let document = PDFDocument()
        for item in items {
            guard let image = NSImage(contentsOf: item.url), let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        let base = first.url.deletingPathExtension().lastPathComponent
        var target = first.url.deletingLastPathComponent().appendingPathComponent("\(base).pdf")
        var index = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = first.url.deletingLastPathComponent().appendingPathComponent("\(base) \(index).pdf")
            index += 1
        }
        if document.write(to: target) {
            add([target])
            flash("Made \(target.lastPathComponent)")
        } else {
            flash("Couldn't write the PDF there")
        }
    }

    private func flash(_ message: String) {
        lastMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.lastMessage == message { self?.lastMessage = nil }
        }
    }

    fileprivate func loadThumbnail(_ item: ShelfItem) {
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 88, height: 88),
                                                   scale: 2, representationTypes: .thumbnail)
        let url = item.url
        guard thumbnails[url] == nil else { return }
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in
                self?.thumbnails[url] = image ?? NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }

    private func save() {
        guard !isDemo else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: storeURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: historyURL, options: .atomic) }
    }
}

extension ShelfStore {
    /// In memory only: demo files never overwrite the real shelf on disk.
    func loadDemo(_ urls: [URL], past: [URL]) {
        isDemo = true
        items = urls.map { ShelfItem(id: UUID(), url: $0, addedAt: .now) }
        history = items + past.enumerated().map { index, url in
            ShelfItem(id: UUID(), url: url, addedAt: .now - Double(index + 1) * 2_700)
        }
        (items + history).forEach(loadThumbnail)
    }
}
