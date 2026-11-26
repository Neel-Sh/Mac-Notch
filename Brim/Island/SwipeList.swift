import SwiftUI

/// A list on the island's black: charcoal rows, no separators, and the native trackpad
/// swipe (two fingers left) to reveal one destructive action, as in Mail.
struct SwipeList<Item: Identifiable & Equatable, Row: View>: View {
    let items: [Item]
    var rowHeight: CGFloat? = nil
    var spacing: CGFloat = 6
    let actionTitle: String
    let actionSymbol: String
    @ViewBuilder let row: (Item) -> Row
    let onSwipe: (Item) -> Void

    var body: some View {
        List {
            ForEach(items) { item in
                row(item)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous).fill(Theme.row)
                    )
                    .contextMenu {
                        Button(actionTitle, systemImage: actionSymbol, role: .destructive) {
                            withAnimation(Motion.swap) { onSwipe(item) }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(Motion.swap) { onSwipe(item) }
                        } label: {
                            Label(actionTitle, systemImage: actionSymbol)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: spacing / 2, leading: 0, bottom: spacing / 2, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .animation(Motion.swap, value: items)
    }
}
