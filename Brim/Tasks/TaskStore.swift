import Foundation
import Observation

struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    let createdAt: Date
    var doneAt: Date?
}

/// Quick notes and to-dos, kept in `~/Library/Application Support/Brim/tasks.json`.
@Observable
final class TaskStore {
    private(set) var items: [TaskItem] = []

    @ObservationIgnored private let url = HookScript.directory.appendingPathComponent("tasks.json")

    /// Open items first (newest on top), then what's done, most recently finished first.
    var ordered: [TaskItem] {
        items.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt }
            + items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    var openCount: Int { items.count { !$0.isDone } }

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            items = decoded
        }
    }

    func add(_ text: String) {
        guard let text = text.nilIfBlank else { return }
        items.append(TaskItem(id: UUID(), text: text, isDone: false, createdAt: .now))
        save()
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        items[index].doneAt = items[index].isDone ? .now : nil
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearDone() {
        items.removeAll(where: \.isDone)
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
    }
}
