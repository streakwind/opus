import OpusCore
import SwiftUI

struct GlobalSearchView: View {
    var store: Store
    var onOpen: (SearchResult) -> Void
    var onDismiss: () -> Void
    @State private var query = ""
    @State private var category: SearchCategory?
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool
    private var results: [SearchResult] { SearchIndex(state: store.state).search(query, category: category) }
    private var activeID: String? { results.contains { $0.id == selectedID } ? selectedID : results.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all of Opus", text: $query)
                    .textFieldStyle(.plain).font(.title3)
                    .focused($searchFocused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onSubmit(openSelected)
                    .accessibilityIdentifier("global-search-field")
                Button("Esc", action: onDismiss).keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryButton("All", value: nil)
                    ForEach(SearchCategory.allCases) { value in categoryButton(value.rawValue, value: value) }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if results.isEmpty {
                            ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try another name or category."))
                                .padding(30)
                        }
                        ForEach(results) { result in
                            Button { onOpen(result) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: result.category.icon).frame(width: 22).foregroundStyle(.teal)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title).font(.body.weight(.medium)).lineLimit(1)
                                        Text(result.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(result.category.rawValue).font(.caption).foregroundStyle(.secondary)
                                    if result.id == activeID { Image(systemName: "return").foregroundStyle(.secondary) }
                                }
                                .padding(12).contentShape(Rectangle())
                                .background(result.id == activeID ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain).id(result.id)
                            .accessibilityIdentifier("search-result-" + result.id)
                            .accessibilityAddTraits(result.id == activeID ? .isSelected : [])
                        }
                    }.padding(8)
                }
                .onChange(of: activeID) { _, id in if let id { reader.scrollTo(id) } }
            }
            Divider()
            HStack {
                Text("↑ ↓ Navigate   ↵ Open   ⌘1–9 Categories   Esc Close")
                Spacer()
                Text("\(results.count) results")
            }.font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .frame(width: 700, height: 490)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selectedID = nil }
        .onChange(of: category) { _, _ in selectedID = nil }
    }

    private func categoryButton(_ title: String, value: SearchCategory?) -> some View {
        Button { category = value; searchFocused = true } label: {
            Text(title).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(category == value ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain)
            .keyboardShortcut(KeyEquivalent(Character(String(value.flatMap { SearchCategory.allCases.firstIndex(of: $0) }.map { $0 + 2 } ?? 1))), modifiers: .command)
    }
    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == activeID } ?? 0
        selectedID = results[min(max(index + delta, 0), results.count - 1)].id
    }
    private func openSelected() {
        if let result = results.first(where: { $0.id == activeID }) { onOpen(result) }
    }
}
