import OpusCore
import SwiftUI

struct GlobalSearchView: View {
    var store: Store
    var group: String = ""
    var onOpen: (SearchResult) -> Void
    var onDismiss: () -> Void
    @State private var query = ""
    @State private var category: SearchCategory?
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool
    @State private var index: SearchIndex?
    @State private var results: [SearchResult] = []
    @AppStorage("searchSort") private var sort: SearchSort = .name
    private func refresh() {
        let allowed = Set(store.state.courses.filter { group.isEmpty || $0.group == group }.map(\.id))
        results = (index?.search(query, category: category, sort: sort) ?? []).filter {
            group.isEmpty || $0.category == .pages || $0.courseID == nil || allowed.contains($0.courseID!)
        }
    }
    private var activeID: String? { results.contains { $0.id == selectedID } ? selectedID : results.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(group.isEmpty ? "Search Opus" : "Search \(group)", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 18))
                    .focused($searchFocused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onSubmit(openSelected)
                    .accessibilityIdentifier("global-search-field")
                Button(action: onDismiss) { Text("esc").font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 3).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4)) }.keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(20)
            filterBar
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if results.isEmpty {
                            VStack(spacing: 6) {
                                Text(query.isEmpty ? "Nothing here yet" : "No matches for “\(query)”")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                                Text(query.isEmpty ? "Choose another type to browse." : "Try a different name or type.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 52)
                        }
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    }.padding(8)
                }
                .onChange(of: activeID) { _, id in if let id { reader.scrollTo(id) } }
            }
            Divider()
            HStack {
                Text("↑↓ Move   ↵ Open")
                Text("⌘1–8 Type   ⇧⌘S Sort").foregroundStyle(.tertiary)
                Spacer()
                Text("\(results.count) results")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 10)
        }
        .frame(width: 620, height: 430)
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains([.command, .shift]), press.characters.lowercased() == "s" {
                let modes = SearchSort.allCases
                sort = modes[(modes.firstIndex(of: sort)! + 1) % modes.count]
                return .handled
            }
            if press.modifiers == .command, let number = Int(press.characters), (1...8).contains(number) {
                category = number == 1 ? nil : SearchCategory.allCases[number - 2]
                return .handled
            }
            return .ignored
        }
        .onAppear { index = SearchIndex(state: store.state); refresh(); searchFocused = true }
        .onChange(of: query) { _, _ in selectedID = nil; refresh() }
        .onChange(of: sort) { _, _ in selectedID = nil; refresh() }
        .onChange(of: category) { _, _ in selectedID = nil; refresh() }
    }

    private var filterBar: some View {
            HStack(spacing: 16) {
                Menu {
                    categoryButton("All types", value: nil)
                    Divider()
                    ForEach(SearchCategory.allCases) { value in categoryButton(value.rawValue, value: value) }
                } label: {
                    HStack(spacing: 6) {
                        Text(category?.rawValue ?? "All types")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                    }
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Spacer()
                Menu {
                    ForEach(SearchSort.allCases) { value in
                        Button { sort = value } label: {
                            if sort == value { Label(value.rawValue, systemImage: "checkmark") } else { Text(value.rawValue) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 10))
                        Text(sort.rawValue)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                    }
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Sort results · ⇧⌘S to cycle")
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 14)
    }
    private func resultRow(_ result: SearchResult) -> some View {
                            Button { onOpen(result) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: result.category.icon).font(.system(size: 14)).frame(width: 26, height: 28).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title).font(.body.weight(.medium)).lineLimit(1)
                                        Text(result.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(result.category.rawValue).font(.caption).foregroundStyle(.secondary)
                                    if result.id == activeID { Image(systemName: "return").foregroundStyle(.secondary) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                                .background(result.id == activeID ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain).id(result.id)
                            .accessibilityIdentifier("search-result-" + result.id)
                            .accessibilityAddTraits(result.id == activeID ? .isSelected : [])
    }
    private func categoryButton(_ title: String, value: SearchCategory?) -> some View {
        Button { category = value; searchFocused = true } label: {
            if category == value { Label(title, systemImage: "checkmark") } else { Text(title) }
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
