import SwiftUI

struct TasksPage: View {
    let store: TaskStore
    let model: IslandModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            composer
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
        .onChange(of: focused) { _, isFocused in model.isEditing = isFocused }
    }

    private var composer: some View {
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
            if store.items.contains(where: \.isDone) {
                Button("Clear Done") { withAnimation(Motion.swap) { store.clearDone() } }
                    .buttonStyle(PillButtonStyle(kind: .quiet))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
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
