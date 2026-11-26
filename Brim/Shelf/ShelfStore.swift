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
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    var lastMessage: String?

    @ObservationIgnored private let storeURL = HookScript.directory.appendingPathComponent("shelf.json")

    init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            items.forEach(loadThumbnail)
        }
    }

    var urls: [URL] { items.map(\.url) }
    var canMakePDF: Bool { !items.isEmpty && items.allSatisfy(\.isImage) }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let fresh = urls.filter { !known.contains($0) }.map { ShelfItem(id: UUID(), url: $0, addedAt: .now) }
        items.append(contentsOf: fresh)
        fresh.forEach(loadThumbnail)
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        thumbnails[id] = nil
        save()
    }

    func clear() {
        items.removeAll()
        thumbnails.removeAll()
        save()
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
        let id = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in
                self?.thumbnails[id] = image ?? NSWorkspace.shared.icon(forFile: item.url.path)
            }
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: storeURL, options: .atomic) }
    }
}

extension ShelfStore {
    /// In memory only: demo files never overwrite the real shelf on disk.
    func loadDemo(_ urls: [URL]) {
        items = urls.map { ShelfItem(id: UUID(), url: $0, addedAt: .now) }
        items.forEach(loadThumbnail)
    }
}
