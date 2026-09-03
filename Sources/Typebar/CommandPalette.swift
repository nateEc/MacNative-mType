import SwiftUI

struct CommandPaletteItem: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]
}

enum ThemeCommandTarget: Equatable {
    case builtIn(AppTheme)
    case custom(UUID)
}

/// Flattens the reference theme subgroup for the native searchable palette.
/// Theme colors and names are Typebar-owned; this only preserves the quick
/// selection behavior and favorite-first ordering.
enum ThemeCommandCatalog {
    private struct Option {
        let target: ThemeCommandTarget
        let title: String
        let subtitle: String
        let keywords: [String]
        let isFavorite: Bool
    }

    static func identifier(for target: ThemeCommandTarget) -> String {
        switch target {
        case .builtIn(let theme): "theme.builtin.\(theme.rawValue)"
        case .custom(let id): "theme.custom.\(id.uuidString.lowercased())"
        }
    }

    static func target(for identifier: String) -> ThemeCommandTarget? {
        if let rawValue = identifier.split(separator: ".").last,
            identifier.hasPrefix("theme.builtin."),
            let theme = AppTheme(rawValue: String(rawValue))
        {
            return .builtIn(theme)
        }
        if let rawValue = identifier.split(separator: ".").last,
            identifier.hasPrefix("theme.custom."),
            let id = UUID(uuidString: String(rawValue))
        {
            return .custom(id)
        }
        return nil
    }

    static func items(
        builtInThemes: [AppTheme] = AppTheme.allCases,
        customThemes: [CustomThemeDefinition],
        favoriteThemeIDs: [String]
    ) -> [CommandPaletteItem] {
        let favorites = Set(favoriteThemeIDs)
        let builtIns = builtInThemes.map { theme in
            Option(
                target: .builtIn(theme), title: "切换主题：\(theme.displayName)",
                subtitle: favorites.contains(ThemeFavoritePolicy.builtInID(for: theme))
                    ? "内置主题 · 已收藏" : "内置主题",
                keywords: ["theme", "主题", theme.displayName, theme.rawValue],
                isFavorite: favorites.contains(ThemeFavoritePolicy.builtInID(for: theme)))
        }
        let customs = customThemes.map { theme in
            Option(
                target: .custom(theme.id), title: "切换主题：\(theme.name)",
                subtitle: favorites.contains(ThemeFavoritePolicy.customID(for: theme.id))
                    ? "自定义主题 · 已收藏" : "自定义主题",
                keywords: ["theme", "主题", "custom", "自定义", theme.name],
                isFavorite: favorites.contains(ThemeFavoritePolicy.customID(for: theme.id)))
        }

        return (builtIns + customs)
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .map { option in
                CommandPaletteItem(
                    id: identifier(for: option.target), title: option.title, subtitle: option.subtitle,
                    systemImage: "paintpalette", keywords: option.keywords)
            }
    }
}

struct PresetCommandEntry: Equatable {
    let id: UUID
    let name: String
    let definition: SavedTestPreset
}

enum PresetCommandCatalog {
    static func identifier(for presetID: UUID) -> String {
        "preset.\(presetID.uuidString.lowercased())"
    }

    static func presetID(for identifier: String) -> UUID? {
        guard identifier.hasPrefix("preset."),
            let rawValue = identifier.split(separator: ".").last
        else { return nil }
        return UUID(uuidString: String(rawValue))
    }

    static func items(presets: [PresetCommandEntry]) -> [CommandPaletteItem] {
        presets.map { preset in
            CommandPaletteItem(
                id: identifier(for: preset.id), title: "应用预设：\(preset.name)",
                subtitle: preset.definition.summaryDescription, systemImage: "slider.horizontal.3",
                keywords: ["preset", "预设", "apply", "应用", preset.name])
        }
    }
}

enum ChallengeCommandCatalog {
    static func identifier(for challengeID: String) -> String {
        "challenge.\(challengeID)"
    }

    static func challengeID(for identifier: String) -> String? {
        let prefix = "challenge."
        guard identifier.hasPrefix(prefix) else { return nil }
        let id = String(identifier.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    static func items(challenges: [TypebarChallenge]) -> [CommandPaletteItem] {
        challenges.map { challenge in
            CommandPaletteItem(
                id: identifier(for: challenge.id), title: "加载挑战：\(challenge.title)",
                subtitle: "\(challenge.description) · \(challenge.requirements.summary)",
                systemImage: "flag.checkered",
                keywords: ["challenge", "挑战", "load", "加载", challenge.title])
        }
    }
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
