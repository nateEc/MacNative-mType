import SwiftUI

struct CommandPaletteItem: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]
}

enum CommandPaletteSearch {
    static func results(items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        let query = normalized(query)
        guard !query.isEmpty else { return items }

        return items.filter { item in
            normalized(item.title).contains(query)
                || normalized(item.subtitle).contains(query)
                || item.keywords.contains { normalized($0).contains(query) }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [CommandPaletteItem]
    let onSelect: (CommandPaletteItem) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [CommandPaletteItem] {
        CommandPaletteSearch.results(items: items, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索命令…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button("清除") { query = "" }
                        .buttonStyle(.borderless)
                }
            }
            .padding(14)

            Divider()

            if results.isEmpty {
                ContentUnavailableView("没有匹配的命令", systemImage: "command", description: Text("试试“历史”、“模式”或“设置”。"))
                    .frame(maxHeight: .infinity)
            } else {
                List(results) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage)
                                .frame(width: 18)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 480, height: 390)
        .onAppear { searchFocused = true }
    }
}
