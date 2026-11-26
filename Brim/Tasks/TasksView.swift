import SwiftUI

struct TasksPage: View {
    let store: TaskStore
    let model: IslandModel
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.islandStyle) private var style

    var body: some View {
        Group {
            if style.edge.isSide { portrait } else { landscape }
        }
        .onChange(of: focused) { _, isFocused in model.isEditing = isFocused }
    }

    /// Docked: how much is left, the list, and the composer at the foot where the hand already is.
    private var portrait: some View {
        VStack(spacing: 10) {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.bottom, 4)
                    Text("Nothing to do")
                        .font(Theme.title(13.5))
                        .foregroundStyle(Theme.secondary)
                    Text("Quick notes and to-dos live here.")
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let done = store.items.count { $0.isDone }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.openCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: Double(store.openCount)))
                    Text("to do")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.tertiary)
                    Spacer(minLength: 8)
                    if done > 0 {
                        Button("Clear \(done) Done") { withAnimation(Motion.swap) { store.clearDone() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.working)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 4)
                .animation(Motion.swap, value: store.openCount)
                .animation(Motion.swap, value: done)

                SwipeList(items: store.ordered, rowHeight: 38, actionTitle: "Delete", actionSymbol: "trash") { item in
                    TaskRow(item: item) { store.toggle(item.id) }
                } onSwipe: { item in
                    store.delete(item.id)
                }
            }
            composer(clears: false)
        }
    }

    private var landscape: some View {
        VStack(spacing: 8) {
            composer(clears: true)
            if store.items.isEmpty {
                Text("Quick notes and to-dos live here.")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            } else {
                SwipeList(items: store.ordered, rowHeight: 34, actionTitle: "Delete", actionSymbol: "trash") { item in
                    TaskRow(item: item) { store.toggle(item.id) }
                } onSwipe: { item in
                    store.delete(item.id)
                }
            }
        }
    }

    private func composer(clears: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.tertiary)
            TextField("Add a task or note", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit {
                    withAnimation(Motion.swap) { store.add(draft) }
                    draft = ""
                }
            if clears, store.items.contains(where: \.isDone) {
                Button("Clear Done") { withAnimation(Motion.swap) { store.clearDone() } }
                    .buttonStyle(PillButtonStyle(kind: .quiet))
                    .padding(.trailing, -6)
            }
        }
        .padding(.horizontal, clears ? 12 : 14)
        .frame(height: clears ? 34 : 38)
        .background(Capsule().fill(Color.white.opacity(focused ? 0.11 : 0.07)))
        .animation(Motion.tap, value: focused)
    }
}

private struct TaskRow: View {
    let item: TaskItem
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isDone ? Theme.done : Theme.tertiary, lineWidth: 1.6)
                    if item.isDone {
                        Circle().fill(Theme.done)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 17, height: 17)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(Motion.tap, value: item.isDone)

            Text(item.text)
                .font(Theme.body(12.5))
                .foregroundStyle(item.isDone ? Theme.tertiary : Theme.primary)
                .strikethrough(item.isDone, color: Theme.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }
}
