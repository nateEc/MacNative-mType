import SwiftUI

private struct OpenCommandPaletteFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openCommandPalette: (() -> Void)? {
        get { self[OpenCommandPaletteFocusedValueKey.self] }
        set { self[OpenCommandPaletteFocusedValueKey.self] = newValue }
    }
}

struct CommandPaletteCommands: Commands {
    @FocusedValue(\.openCommandPalette) private var openCommandPalette

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("打开命令面板") { openCommandPalette?() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(openCommandPalette == nil)
        }
    }
}

enum CommandPaletteDynamicShortcut: Equatable {
    case escape
    case tab
    case shiftTab

    static func resolve(
        quickRestartKey: QuickRestartKey, promptAcceptsTab: Bool
    ) -> Self {
        guard quickRestartKey == .escape else { return .escape }
        return promptAcceptsTab ? .shiftTab : .tab
    }

    var displayName: String {
        switch self {
        case .escape: "Esc"
        case .tab: "Tab"
        case .shiftTab: "⇧Tab"
        }
    }

    func matches(charactersIgnoringModifiers: String?, shiftPressed: Bool) -> Bool {
        switch self {
        case .escape:
            charactersIgnoringModifiers == "\u{1B}" && !shiftPressed
        case .tab:
            charactersIgnoringModifiers == "\t" && !shiftPressed
        case .shiftTab:
            charactersIgnoringModifiers == "\t" && shiftPressed
        }
    }
}

/// Controls whether the command palette starts as a global command search or
/// exposes the same commands through native navigation groups.
enum CommandPaletteListMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case singleList
    case grouped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleList: "单列表"
        case .grouped: "分组导航"
        }
    }
}

enum CommandPaletteGroup: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case practice
    case library
    case appearance
    case activity
    case data
    case connections
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: "练习与模式"
        case .library: "文本、预设与挑战"
        case .appearance: "主题与外观"
        case .activity: "成绩与历史"
        case .data: "数据与分享"
        case .connections: "同步与社交"
        case .settings: "应用设置"
        }
    }

    var subtitle: String {
        switch self {
        case .practice: "重开练习或切换测试模式"
        case .library: "打开已保存内容或加载本机挑战"
        case .appearance: "选择内置或自定义主题"
        case .activity: "查看本机成绩和趋势"
        case .data: "导入、导出或分享测试配置"
        case .connections: "管理自建同步、好友和通知"
        case .settings: "修改输入、显示和账户选项"
        }
    }

    var systemImage: String {
        switch self {
        case .practice: "keyboard"
        case .library: "books.vertical"
        case .appearance: "paintpalette"
        case .activity: "chart.line.uptrend.xyaxis"
        case .data: "externaldrive"
        case .connections: "person.2"
        case .settings: "gearshape"
        }
    }

    var keywords: [String] {
        switch self {
        case .practice: ["practice", "test", "mode", "练习", "测试", "模式", "重开"]
        case .library: ["library", "preset", "challenge", "text", "文本", "预设", "挑战"]
        case .appearance: ["appearance", "theme", "主题", "外观"]
        case .activity: ["activity", "history", "result", "成绩", "历史", "统计"]
        case .data: ["data", "share", "backup", "数据", "分享", "备份"]
        case .connections: ["sync", "friend", "notification", "同步", "好友", "通知"]
        case .settings: ["setting", "settings", "设置", "偏好"]
        }
    }
}

struct CommandPaletteItem: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]
    let group: CommandPaletteGroup

    init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        keywords: [String],
        group: CommandPaletteGroup = .practice
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.group = group
    }
}

enum QuickTestParameterCommandTarget: Equatable {
    case timed(Int)
    case words(Int)
    case punctuation(Bool)
    case numbers(Bool)
}

/// Exposes the reference command palette's standard time, word, punctuation,
/// and number choices without copying its command implementation or labels.
enum QuickTestParameterCommandCatalog {
    private static let durations = [15, 30, 60, 120]
    private static let wordCounts = [10, 25, 50, 100]

    static var items: [CommandPaletteItem] {
        let timed = durations.map { seconds in
            CommandPaletteItem(
                id: "test.time.\(seconds)", title: "时间练习：\(seconds) 秒",
                subtitle: "切换到时间模式并立即重开", systemImage: "timer",
                keywords: ["time", "duration", "时间", "时长", "\(seconds)"], group: .practice)
        }
        let words = wordCounts.map { count in
            CommandPaletteItem(
                id: "test.words.\(count)", title: "字数练习：\(count) 词",
                subtitle: "切换到字数模式并立即重开", systemImage: "text.word.spacing",
                keywords: ["words", "count", "字数", "词数", "\(count)"], group: .practice)
        }
        let options = [
            optionItem(kind: "punctuation", enabled: true, title: "开启标点", keyword: "标点"),
            optionItem(kind: "punctuation", enabled: false, title: "关闭标点", keyword: "标点"),
            optionItem(kind: "numbers", enabled: true, title: "开启数字", keyword: "数字"),
            optionItem(kind: "numbers", enabled: false, title: "关闭数字", keyword: "数字"),
        ]
        return timed + words + options
    }

    static func target(for identifier: String) -> QuickTestParameterCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "test" else { return nil }
        let value = String(parts[2])
        switch parts[1] {
        case "time":
            guard let seconds = Int(value), durations.contains(seconds) else { return nil }
            return .timed(seconds)
        case "words":
            guard let count = Int(value), wordCounts.contains(count) else { return nil }
            return .words(count)
        case "punctuation":
            guard let enabled = enabledValue(value) else { return nil }
            return .punctuation(enabled)
        case "numbers":
            guard let enabled = enabledValue(value) else { return nil }
            return .numbers(enabled)
        default:
            return nil
        }
    }

    private static func optionItem(
        kind: String, enabled: Bool, title: String, keyword: String
    ) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "test.\(kind).\(enabled ? "on" : "off")", title: title,
            subtitle: "更新内容选项并立即重开", systemImage: enabled ? "checkmark.circle" : "xmark.circle",
            keywords: [kind, enabled ? "on" : "off", keyword, enabled ? "开启" : "关闭"],
            group: .practice)
    }

    private static func enabledValue(_ value: String) -> Bool? {
        switch value {
        case "on": true
        case "off": false
        default: nil
        }
    }
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
                    systemImage: "paintpalette", keywords: option.keywords, group: .appearance)
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
                keywords: ["preset", "预设", "apply", "应用", preset.name], group: .library)
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
                keywords: ["challenge", "挑战", "load", "加载", challenge.title], group: .library)
        }
    }
}

enum QuoteFavoriteCommand {
    static let identifier = "quote.favorite"

    static func item(currentQuoteID: String?, isFavorite: Bool) -> CommandPaletteItem? {
        guard currentQuoteID != nil else { return nil }
        return CommandPaletteItem(
            id: identifier,
            title: isFavorite ? "取消收藏当前引语" : "收藏当前引语",
            subtitle: isFavorite ? "从本机引语收藏中移除" : "加入本机引语收藏",
            systemImage: isFavorite ? "heart.slash" : "heart",
            keywords: ["quote", "引语", "favorite", "收藏"])
    }
}

struct CompletedResultCommandAvailability: Equatable {
    let hasCopyableWords: Bool
    let hasWordHistory: Bool
    let hasMissedWordPractice: Bool
    let hasSlowWordPractice: Bool
    let hasCombinedPractice: Bool
    let hasConfigurablePractice: Bool
}

enum CompletedResultCommandAction: String, Equatable {
    case next
    case repeatTest = "repeat"
    case practiceMissed
    case practiceSlow
    case practiceCombined
    case configurePractice
    case toggleWordHistory
    case copyWords
    case copyImage
    case saveImage

    var identifier: String { "result.\(rawValue)" }
}

/// Exposes completed-result actions only when the current result has the data
/// needed to perform them. The actions themselves stay owned by the result
/// screen so toolbar buttons and command selection cannot diverge.
enum CompletedResultCommandCatalog {
    static func action(for identifier: String) -> CompletedResultCommandAction? {
        let prefix = "result."
        guard identifier.hasPrefix(prefix) else { return nil }
        return CompletedResultCommandAction(rawValue: String(identifier.dropFirst(prefix.count)))
    }

    static func items(
        availability: CompletedResultCommandAvailability
    ) -> [CommandPaletteItem] {
        var actions: [CompletedResultCommandAction] = [.next, .repeatTest]
        if availability.hasMissedWordPractice { actions.append(.practiceMissed) }
        if availability.hasSlowWordPractice { actions.append(.practiceSlow) }
        if availability.hasCombinedPractice { actions.append(.practiceCombined) }
        if availability.hasConfigurablePractice { actions.append(.configurePractice) }
        if availability.hasWordHistory { actions.append(.toggleWordHistory) }
        if availability.hasCopyableWords { actions.append(.copyWords) }
        actions.append(contentsOf: [.copyImage, .saveImage])
        return actions.map(item(for:))
    }

    private static func item(for action: CompletedResultCommandAction) -> CommandPaletteItem {
        switch action {
        case .next:
            CommandPaletteItem(
                id: action.identifier, title: "再来一次", subtitle: "按当前选择生成新的练习",
                systemImage: "chevron.right", keywords: ["next", "restart", "下一轮", "重开"],
                group: .practice)
        case .repeatTest:
            CommandPaletteItem(
                id: action.identifier, title: "重复本轮", subtitle: "保留本轮配置和提示重新练习",
                systemImage: "arrow.triangle.2.circlepath", keywords: ["repeat", "重复", "同一提示"],
                group: .practice)
        case .practiceMissed:
            CommandPaletteItem(
                id: action.identifier, title: "练习错词", subtitle: "按本轮错误频次生成练习",
                systemImage: "exclamationmark.triangle", keywords: ["missed", "wrong", "错词", "练习"],
                group: .practice)
        case .practiceSlow:
            CommandPaletteItem(
                id: action.identifier, title: "练习慢词", subtitle: "按本轮最慢的可测单词生成练习",
                systemImage: "tortoise", keywords: ["slow", "慢词", "练习"], group: .practice)
        case .practiceCombined:
            CommandPaletteItem(
                id: action.identifier, title: "练习错词与慢词", subtitle: "合并本轮两类弱项生成练习",
                systemImage: "scope", keywords: ["both", "combined", "错词", "慢词", "练习"],
                group: .practice)
        case .configurePractice:
            CommandPaletteItem(
                id: action.identifier, title: "自选弱项练习…", subtitle: "组合错词、上下文和慢词",
                systemImage: "slider.horizontal.3", keywords: ["custom", "configure", "自选", "错词", "慢词"],
                group: .practice)
        case .toggleWordHistory:
            CommandPaletteItem(
                id: action.identifier, title: "展开或收起单词历史", subtitle: "切换本轮目标与实际输入对照",
                systemImage: "text.alignleft", keywords: ["toggle", "history", "单词", "历史"],
                group: .activity)
        case .copyWords:
            CommandPaletteItem(
                id: action.identifier, title: "复制已练习词", subtitle: "复制本轮实际到达的目标内容",
                systemImage: "doc.on.doc", keywords: ["copy", "words", "复制", "提示"], group: .data)
        case .copyImage:
            CommandPaletteItem(
                id: action.identifier, title: "复制结果图片", subtitle: "将 Typebar 结果卡复制到剪贴板",
                systemImage: "photo.on.rectangle", keywords: ["copy", "image", "截图", "图片"],
                group: .data)
        case .saveImage:
            CommandPaletteItem(
                id: action.identifier, title: "保存结果图片…", subtitle: "将 Typebar 结果卡导出为 PNG",
                systemImage: "square.and.arrow.down", keywords: ["save", "download", "PNG", "保存", "图片"],
                group: .data)
        }
    }
}

enum CompletedResultPracticeMissedSelection: String, CaseIterable, Equatable, Identifiable {
    case off
    case words
    case context

    var id: Self { self }

    var displayName: String {
        switch self {
        case .off: "不加入错词"
        case .words: "错词"
        case .context: "错词 + 前词上下文"
        }
    }
}

struct CompletedResultPracticeSelection: Equatable {
    var missed: CompletedResultPracticeMissedSelection
    var includesSlow: Bool
}

struct CompletedResultPracticeAvailability: Equatable {
    let hasMissed: Bool
    let hasContextualMissed: Bool
    let hasSlow: Bool
    let hasMissedAndSlow: Bool
    let hasContextualMissedAndSlow: Bool

    var hasAny: Bool { hasMissed || hasContextualMissed || hasSlow }
}

enum CompletedResultPracticeRoute: Equatable {
    case missed
    case contextualMissed
    case slow
    case missedAndSlow
    case contextualMissedAndSlow
}

enum CompletedResultPracticePolicy {
    static func missedChoices(
        availability: CompletedResultPracticeAvailability
    ) -> [CompletedResultPracticeMissedSelection] {
        var choices: [CompletedResultPracticeMissedSelection] = [.off]
        if availability.hasMissed { choices.append(.words) }
        if availability.hasContextualMissed { choices.append(.context) }
        return choices
    }

    static func defaultSelection(
        availability: CompletedResultPracticeAvailability
    ) -> CompletedResultPracticeSelection {
        if availability.hasMissed { return .init(missed: .words, includesSlow: false) }
        if availability.hasContextualMissed { return .init(missed: .context, includesSlow: false) }
        return .init(missed: .off, includesSlow: availability.hasSlow)
    }

    static func route(
        selection: CompletedResultPracticeSelection,
        availability: CompletedResultPracticeAvailability
    ) -> CompletedResultPracticeRoute? {
        switch (selection.missed, selection.includesSlow) {
        case (.off, false): nil
        case (.off, true): availability.hasSlow ? .slow : nil
        case (.words, false): availability.hasMissed ? .missed : nil
        case (.words, true): availability.hasMissedAndSlow ? .missedAndSlow : nil
        case (.context, false): availability.hasContextualMissed ? .contextualMissed : nil
        case (.context, true):
            availability.hasContextualMissedAndSlow ? .contextualMissedAndSlow : nil
        }
    }
}

enum CommandPaletteSearch {
    static func results(items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        return items.filter { item in
            matches(query: query, terms: [item.title, item.subtitle] + item.keywords)
        }
    }

    static func matches(query: String, terms: [String]) -> Bool {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return true }
        return terms.contains { normalized($0).contains(normalizedQuery) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CommandPaletteBrowseDestination: Equatable {
    case groups([CommandPaletteGroup])
    case items([CommandPaletteItem])
}

/// Keeps command palette navigation deterministic and independent of SwiftUI.
/// A leading `>` is the explicit escape hatch from grouped navigation to the
/// global command list, matching the reference command-line interaction.
enum CommandPaletteBrowsePolicy {
    static func destination(
        items: [CommandPaletteItem],
        listMode: CommandPaletteListMode,
        selectedGroup: CommandPaletteGroup?,
        query: String
    ) -> CommandPaletteBrowseDestination {
        switch listMode {
        case .singleList:
            return .items(CommandPaletteSearch.results(items: items, query: query))
        case .grouped:
            if isGlobalSearch(query) {
                return .items(CommandPaletteSearch.results(
                    items: items, query: globalSearchQuery(query)))
            }
            if let selectedGroup {
                return .items(CommandPaletteSearch.results(
                    items: items.filter { $0.group == selectedGroup }, query: query))
            }
            let availableGroups = Set(items.map(\.group))
            return .groups(CommandPaletteGroup.allCases.filter {
                availableGroups.contains($0)
                    && CommandPaletteSearch.matches(
                        query: query, terms: [$0.title, $0.subtitle] + $0.keywords)
            })
        }
    }

    static func isGlobalSearch(_ query: String) -> Bool {
        query.first == ">"
    }

    static func globalSearchQuery(_ query: String) -> String {
        guard isGlobalSearch(query) else { return query }
        return String(query.dropFirst())
    }
}

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [CommandPaletteItem]
    let listMode: CommandPaletteListMode
    let onSelect: (CommandPaletteItem) -> Void
    @State private var query = ""
    @State private var selectedGroup: CommandPaletteGroup?
    @FocusState private var searchFocused: Bool

    private var destination: CommandPaletteBrowseDestination {
        CommandPaletteBrowsePolicy.destination(
            items: items, listMode: listMode, selectedGroup: selectedGroup, query: query)
    }

    private var isGlobalSearch: Bool {
        listMode == .grouped && CommandPaletteBrowsePolicy.isGlobalSearch(query)
    }

    private var searchPlaceholder: String {
        if isGlobalSearch { return "搜索全部命令…" }
        if let selectedGroup { return "搜索\(selectedGroup.title)…" }
        switch listMode {
        case .singleList: return "搜索全部命令…"
        case .grouped: return "选择分类，或输入 > 搜索全部…"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if listMode == .grouped, selectedGroup != nil, !isGlobalSearch {
                    Button {
                        selectedGroup = nil
                        query = ""
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("返回命令分类")
                }
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button("清除") { query = "" }
                        .buttonStyle(.borderless)
                }
            }
            .padding(14)

            Divider()

            switch destination {
            case .groups(let groups):
                if groups.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的命令分类", systemImage: "command",
                        description: Text("输入 > 可直接搜索全部命令。"))
                    .frame(maxHeight: .infinity)
                } else {
                    List(groups) { group in
                        Button {
                            selectedGroup = group
                            query = ""
                        } label: {
                            groupRow(group)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            case .items(let results):
                if results.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的命令", systemImage: "command",
                        description: Text("试试“历史”、“模式”或“设置”。"))
                    .frame(maxHeight: .infinity)
                } else {
                    List(results) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            commandRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .frame(width: 480, height: 390)
        .onAppear { searchFocused = true }
    }

    private func groupRow(_ group: CommandPaletteGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.systemImage)
                .frame(width: 18)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func commandRow(_ item: CommandPaletteItem) -> some View {
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
}
