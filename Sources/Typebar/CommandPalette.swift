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
    case customTime
    case customWords
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
        let customTime = CommandPaletteItem(
            id: "test.time.custom", title: "时间练习：自定义…",
            subtitle: "输入任意非负整数秒；0 表示无限", systemImage: "timer",
            keywords: ["time", "duration", "custom", "时间", "时长", "自定义"], group: .practice)
        let words = wordCounts.map { count in
            CommandPaletteItem(
                id: "test.words.\(count)", title: "字数练习：\(count) 词",
                subtitle: "切换到字数模式并立即重开", systemImage: "text.word.spacing",
                keywords: ["words", "count", "字数", "词数", "\(count)"], group: .practice)
        }
        let customWords = CommandPaletteItem(
            id: "test.words.custom", title: "字数练习：自定义…",
            subtitle: "输入任意非负整数词数；0 表示无限", systemImage: "text.word.spacing",
            keywords: ["words", "count", "custom", "字数", "词数", "自定义"], group: .practice)
        let options = [
            optionItem(kind: "punctuation", enabled: true, title: "开启标点", keyword: "标点"),
            optionItem(kind: "punctuation", enabled: false, title: "关闭标点", keyword: "标点"),
            optionItem(kind: "numbers", enabled: true, title: "开启数字", keyword: "数字"),
            optionItem(kind: "numbers", enabled: false, title: "关闭数字", keyword: "数字"),
        ]
        return timed + [customTime] + words + [customWords] + options
    }

    static func target(for identifier: String) -> QuickTestParameterCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "test" else { return nil }
        let value = String(parts[2])
        switch parts[1] {
        case "time":
            if value == "custom" { return .customTime }
            guard let seconds = Int(value), durations.contains(seconds) else { return nil }
            return .timed(seconds)
        case "words":
            if value == "custom" { return .customWords }
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

enum QuoteCommandTarget: Equatable {
    case lengths(Set<QuoteLength>)
    case favorites
    case search
}

enum QuoteCommandCatalog {
    static func items(hasFavorites: Bool) -> [CommandPaletteItem] {
        var values: [(String, String, String)] = [
            ("all", "引语长度：全部", "使用全部四档原创引语"),
            ("short", "引语长度：短", "只使用短引语"),
            ("medium", "引语长度：中", "只使用中等长度引语"),
            ("long", "引语长度：长", "只使用长引语"),
            ("extended", "引语长度：超长", "只使用超长引语"),
        ]
        if hasFavorites {
            values.append(("favorites", "引语：本机收藏", "只使用当前语言和来源的收藏"))
        }
        values.append(("search", "搜索引语", "切换到仅在本机筛选的引语搜索"))
        return values.map { value, title, subtitle in
            CommandPaletteItem(
                id: "test.quote.\(value)", title: title, subtitle: subtitle,
                systemImage: value == "search" ? "magnifyingglass" : "quote.opening",
                keywords: ["quote", "quotes", "引语", "长度", value], group: .practice)
        }
    }

    static func target(for identifier: String) -> QuoteCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "test", parts[1] == "quote" else { return nil }
        switch parts[2] {
        case "all": return .lengths(QuoteLengthSelection.selectable)
        case "short": return .lengths([.short])
        case "medium": return .lengths([.medium])
        case "long": return .lengths([.long])
        case "extended": return .lengths([.extended])
        case "favorites": return .favorites
        case "search": return .search
        default: return nil
        }
    }
}

enum LanguageCommandCatalog {
    static func items(languages: [TypingLanguage]) -> [CommandPaletteItem] {
        languages.map { language in
            CommandPaletteItem(
                id: "test.language.\(language.rawValue)",
                title: "切换语言：\(language.displayName)",
                subtitle: language.isCodeLanguage ? "使用本机原创代码练习" : "使用本机原创词流",
                systemImage: language.isCodeLanguage
                    ? "chevron.left.forwardslash.chevron.right" : "character.book.closed",
                keywords: ["language", "语言", "词表", language.displayName, language.rawValue],
                group: .practice)
        }
    }

    static func target(for identifier: String) -> TypingLanguage? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "test", parts[1] == "language" else { return nil }
        return TypingLanguage(rawValue: String(parts[2]))
    }
}

enum PracticePreferenceCommandTarget: Equatable {
    case difficulty(Difficulty)
    case repeatQuotes(Bool)
    case saveCompletedResults(Bool)
    case englishVariant(EnglishVariant)

    var requiresRestart: Bool {
        switch self {
        case .difficulty, .englishVariant: true
        case .repeatQuotes, .saveCompletedResults: false
        }
    }

    var exitsChallenge: Bool { requiresRestart }

}

enum PracticePreferenceCommandCatalog {
    static let items: [CommandPaletteItem] = [
        .init(
            id: "test.difficulty.normal", title: "难度：普通", subtitle: "错误不会提前结束练习",
            systemImage: "star", keywords: ["difficulty", "normal", "难度", "普通"], group: .practice),
        .init(
            id: "test.difficulty.expert", title: "难度：专家", subtitle: "提交错误单词时结束练习",
            systemImage: "exclamationmark.triangle", keywords: ["difficulty", "expert", "难度", "专家"], group: .practice),
        .init(
            id: "test.difficulty.master", title: "难度：大师", subtitle: "首次错误按键时结束练习",
            systemImage: "star.fill", keywords: ["difficulty", "master", "难度", "大师"], group: .practice),
        .init(
            id: "test.repeatQuotes.off", title: "引语重开：换一条", subtitle: "重开时继续引语随机队列",
            systemImage: "shuffle", keywords: ["repeat", "quote", "引语", "重开", "换一条"], group: .practice),
        .init(
            id: "test.repeatQuotes.typing", title: "引语重开：重复当前", subtitle: "输入开始后重开仍使用当前引语",
            systemImage: "repeat", keywords: ["repeat", "quote", "typing", "引语", "重复"], group: .practice),
        .init(
            id: "test.resultSaving.off", title: "保存完成成绩：关闭", subtitle: "结果仍显示，但不进入历史或同步",
            systemImage: "archivebox", keywords: ["result", "saving", "incognito", "成绩", "保存", "关闭"], group: .practice),
        .init(
            id: "test.resultSaving.on", title: "保存完成成绩：开启", subtitle: "完成成绩写入本机历史",
            systemImage: "archivebox.fill", keywords: ["result", "saving", "成绩", "保存", "开启"], group: .practice),
        .init(
            id: "test.englishVariant.american", title: "英文拼写：美式", subtitle: "English 基础词流使用美式拼写",
            systemImage: "character.book.closed", keywords: ["english", "american", "英文", "美式", "拼写"], group: .practice),
        .init(
            id: "test.englishVariant.british", title: "英文拼写：英式", subtitle: "English 基础词流使用英式拼写",
            systemImage: "character.book.closed", keywords: ["english", "british", "英文", "英式", "拼写"], group: .practice),
    ]

    static func target(for identifier: String) -> PracticePreferenceCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "test" else { return nil }
        switch (parts[1], parts[2]) {
        case ("difficulty", "normal"): return .difficulty(.normal)
        case ("difficulty", "expert"): return .difficulty(.expert)
        case ("difficulty", "master"): return .difficulty(.master)
        case ("repeatQuotes", "off"): return .repeatQuotes(false)
        case ("repeatQuotes", "typing"): return .repeatQuotes(true)
        case ("resultSaving", "off"): return .saveCompletedResults(false)
        case ("resultSaving", "on"): return .saveCompletedResults(true)
        case ("englishVariant", "american"): return .englishVariant(.american)
        case ("englishVariant", "british"): return .englishVariant(.british)
        default: return nil
        }
    }
}

enum BehaviorCommandTarget: Equatable {
    case quickRestart(QuickRestartKey)
    case blindMode(Bool)
    case alwaysShowWordsHistory(Bool)
    case commandPaletteListMode(CommandPaletteListMode)

    var requiresRestart: Bool { false }
    var exitsChallenge: Bool { false }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .quickRestart(let key): settings.quickRestartKey = key
        case .blindMode(let enabled): settings.blindMode = enabled
        case .alwaysShowWordsHistory(let enabled): settings.alwaysShowWordsHistory = enabled
        case .commandPaletteListMode(let mode): settings.commandPaletteListMode = mode
        }
    }
}

/// Maps the fixed reference behavior commands to Typebar's existing native
/// preferences without restarting the active test.
enum BehaviorCommandCatalog {
    static let items: [CommandPaletteItem] = [
        option("quickRestart", "off", "快速重开：关闭", "仅保留 ⌘R", "arrow.counterclockwise"),
        option("quickRestart", "esc", "快速重开：Esc", "使用 Esc 重新开始练习", "escape"),
        option("quickRestart", "tab", "快速重开：Tab", "使用 Tab 重新开始练习", "arrow.right.to.line"),
        option("quickRestart", "enter", "快速重开：Enter", "使用 Enter 重新开始练习", "return"),
        toggle("blindMode", false, "盲打", "显示输入正确性", "eye"),
        toggle("blindMode", true, "盲打", "隐藏输入正确性", "eye.slash"),
        toggle(
            "alwaysShowWordsHistory", false, "完成后展开单词历史",
            "结果页默认保持折叠", "text.justify.left"),
        toggle(
            "alwaysShowWordsHistory", true, "完成后展开单词历史",
            "有单词记录时自动展开", "text.justify.left"),
        option(
            "singleListCommandLine", "manual", "命令面板：手动分组",
            "按分组浏览，输入 > 展开全部", "list.bullet.indent"),
        option(
            "singleListCommandLine", "on", "命令面板：单列表",
            "打开时直接展示全部命令", "list.bullet"),
    ]

    static func target(for identifier: String) -> BehaviorCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "behavior" else { return nil }
        let value = String(parts[2])
        switch String(parts[1]) {
        case "quickRestart":
            let keys: [String: QuickRestartKey] = [
                "off": .off, "esc": .escape, "tab": .tab, "enter": .enter,
            ]
            return keys[value].map(BehaviorCommandTarget.quickRestart)
        case "blindMode":
            return boolean(value).map(BehaviorCommandTarget.blindMode)
        case "alwaysShowWordsHistory":
            return boolean(value).map(BehaviorCommandTarget.alwaysShowWordsHistory)
        case "singleListCommandLine":
            let modes: [String: CommandPaletteListMode] = [
                "manual": .grouped, "on": .singleList,
            ]
            return modes[value].map(BehaviorCommandTarget.commandPaletteListMode)
        default:
            return nil
        }
    }

    private static func toggle(
        _ key: String, _ enabled: Bool, _ title: String, _ subtitle: String,
        _ systemImage: String
    ) -> CommandPaletteItem {
        option(
            key, enabled ? "on" : "off", "\(title)：\(enabled ? "开启" : "关闭")",
            subtitle, systemImage)
    }

    private static func option(
        _ key: String, _ value: String, _ title: String, _ subtitle: String,
        _ systemImage: String
    ) -> CommandPaletteItem {
        let identifier = "behavior.\(key).\(value)"
        return CommandPaletteItem(
            id: identifier, title: title, subtitle: subtitle,
            systemImage: systemImage,
            keywords: ["behavior", "行为", key, value, title, identifier], group: .settings)
    }

    private static func boolean(_ value: String) -> Bool? {
        switch value {
        case "on": true
        case "off": false
        default: nil
        }
    }
}

enum InputRuleCommandTarget: Equatable {
    case freedomMode(Bool)
    case strictSpace(Bool)
    case oppositeShiftMode(OppositeShiftMode)
    case stopOnError(StopOnErrorMode)
    case deleteOnError(DeleteOnErrorMode)
    case confidenceMode(ConfidenceMode)
    case quickEnd(Bool)
    case indicateTypos(TypoIndicatorStyle)
    case compositionDisplay(CompositionDisplayStyle)
    case hideExtraLetters(Bool)
    case lazyMode(Bool)
    case codeUnindentOnBackspace(Bool)

    var requiresRestart: Bool {
        switch self {
        case .strictSpace, .stopOnError, .lazyMode, .codeUnindentOnBackspace: true
        case .freedomMode, .oppositeShiftMode, .deleteOnError, .confidenceMode,
             .quickEnd, .indicateTypos, .compositionDisplay, .hideExtraLetters: false
        }
    }

    var exitsChallenge: Bool { requiresRestart }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .freedomMode(let enabled): settings.freedomMode = enabled
        case .strictSpace(let enabled): settings.strictSpace = enabled
        case .oppositeShiftMode(let mode): settings.oppositeShiftMode = mode
        case .stopOnError(let mode): settings.stopOnErrorMode = mode
        case .deleteOnError(let mode): settings.deleteOnErrorMode = mode
        case .confidenceMode(let mode): settings.confidenceMode = mode
        case .quickEnd(let enabled): settings.quickEnd = enabled
        case .indicateTypos(let style): settings.typoIndicatorStyle = style
        case .compositionDisplay(let style): settings.compositionDisplayStyle = style
        case .hideExtraLetters(let enabled): settings.hideExtraLetters = enabled
        case .lazyMode(let enabled):
            settings.testModifiers = TestModifierPolicy.normalized(
                enabled
                    ? settings.testModifiers + [.lazyLatin]
                    : settings.testModifiers.filter { $0 != .lazyLatin })
        case .codeUnindentOnBackspace(let enabled): settings.codeUnindentOnBackspace = enabled
        }
    }
}

/// Mirrors the fixed reference command metadata and schema values while
/// routing every option to Typebar-owned native settings.
enum InputRuleCommandCatalog {
    static let items: [CommandPaletteItem] = [
        toggle("freedomMode", false, "自由回退", "限制回退到已完成的正确单词", "arrow.uturn.backward"),
        toggle("freedomMode", true, "自由回退", "允许删除任何已输入单词", "arrow.uturn.backward"),
        toggle("strictSpace", false, "严格空格", "单词开头的空格不会作为输入", "space"),
        toggle("strictSpace", true, "严格空格", "单词开头的空格也计入输入", "space"),
        option("oppositeShiftMode", "off", "反向 Shift：关闭", "不检查左右 Shift", "shift"),
        option("oppositeShiftMode", "on", "反向 Shift：开启", "强制使用另一只手的 Shift", "shift.fill"),
        option("oppositeShiftMode", "keymap", "反向 Shift：按键位图", "按选定键位图判断左右手", "keyboard"),
        option("stopOnError", "off", "遇错停下：关闭", "错误字符不会阻止继续输入", "hand.raised"),
        option("stopOnError", "word", "遇错停下：单词", "修正当前单词后才能继续", "hand.raised.fill"),
        option("stopOnError", "letter", "遇错停下：字符", "错误字符不会被接受", "hand.raised.fill"),
        option("deleteOnError", "off", "遇错删除：关闭", "保留错误输入", "delete.left"),
        option("deleteOnError", "letter", "遇错删除：字符", "删除错误字符及前一字符", "delete.left.fill"),
        option("deleteOnError", "letter_hard", "遇错删除：字符（硬）", "首字符出错时退回上一词", "delete.left.fill"),
        option("deleteOnError", "word", "遇错删除：单词", "错误时清空当前单词", "delete.backward"),
        option("deleteOnError", "word_hard", "遇错删除：单词（硬）", "首字符出错时退回上一词", "delete.backward.fill"),
        option("confidenceMode", "off", "信心模式：关闭", "允许正常回退修改", "arrow.backward"),
        option("confidenceMode", "on", "信心模式：开启", "不能回到之前的单词", "arrow.backward.circle"),
        option("confidenceMode", "max", "信心模式：最大", "完全禁用退格", "nosign"),
        toggle("quickEnd", false, "最后一词快速结束", "错误的最后一词需要空格确认", "forward.end"),
        toggle("quickEnd", true, "最后一词快速结束", "输入最后一词后立即结束", "forward.end.fill"),
        option("indicateTypos", "off", "错字提示：关闭", "只使用默认错误样式", "exclamationmark"),
        option("indicateTypos", "below", "错字提示：下方", "在目标字符下显示实际输入", "text.below.photo"),
        option("indicateTypos", "replace", "错字提示：替换", "用实际输入替换目标字符", "rectangle.and.pencil.and.ellipsis"),
        option("indicateTypos", "both", "错字提示：两者", "替换字符并在下方显示目标", "square.stack.3d.up"),
        option("compositionDisplay", "off", "组合输入显示：关闭", "仅标记正在组合的位置", "character.cursor.ibeam"),
        option("compositionDisplay", "below", "组合输入显示：下方", "在练习文本下显示组合字符", "text.below.photo"),
        option("compositionDisplay", "replace", "组合输入显示：替换", "在当前位置显示组合字符", "character.cursor.ibeam"),
        toggle("hideExtraLetters", false, "隐藏额外字符", "显示超出目标的输入", "eye"),
        toggle("hideExtraLetters", true, "隐藏额外字符", "隐藏超出目标的输入", "eye.slash"),
        toggle("lazyMode", false, "简化重音输入", "要求输入完整重音和变音字符", "textformat"),
        toggle("lazyMode", true, "简化重音输入", "允许用基础拉丁字母输入重音字符", "textformat"),
        toggle("codeUnindentOnBackspace", false, "代码退格反缩进", "按普通退格规则删除缩进", "decrease.indent"),
        toggle("codeUnindentOnBackspace", true, "代码退格反缩进", "删除行首缩进时返回上一行", "decrease.indent"),
    ]

    static func target(for identifier: String) -> InputRuleCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "input" else { return nil }
        let value = String(parts[2])
        switch String(parts[1]) {
        case "freedomMode": return boolean(value).map(InputRuleCommandTarget.freedomMode)
        case "strictSpace": return boolean(value).map(InputRuleCommandTarget.strictSpace)
        case "oppositeShiftMode": return OppositeShiftMode(rawValue: value).map(InputRuleCommandTarget.oppositeShiftMode)
        case "stopOnError": return StopOnErrorMode(rawValue: value).map(InputRuleCommandTarget.stopOnError)
        case "deleteOnError":
            let values: [String: DeleteOnErrorMode] = [
                "off": .off, "letter": .letter, "letter_hard": .letterHard,
                "word": .word, "word_hard": .wordHard,
            ]
            return values[value].map(InputRuleCommandTarget.deleteOnError)
        case "confidenceMode":
            let values: [String: ConfidenceMode] = ["off": .off, "on": .on, "max": .maximum]
            return values[value].map(InputRuleCommandTarget.confidenceMode)
        case "quickEnd": return boolean(value).map(InputRuleCommandTarget.quickEnd)
        case "indicateTypos": return TypoIndicatorStyle(rawValue: value).map(InputRuleCommandTarget.indicateTypos)
        case "compositionDisplay":
            return CompositionDisplayStyle(rawValue: value).map(InputRuleCommandTarget.compositionDisplay)
        case "hideExtraLetters": return boolean(value).map(InputRuleCommandTarget.hideExtraLetters)
        case "lazyMode": return boolean(value).map(InputRuleCommandTarget.lazyMode)
        case "codeUnindentOnBackspace":
            return boolean(value).map(InputRuleCommandTarget.codeUnindentOnBackspace)
        default: return nil
        }
    }

    private static func toggle(
        _ key: String, _ enabled: Bool, _ title: String, _ subtitle: String, _ systemImage: String
    ) -> CommandPaletteItem {
        option(
            key, enabled ? "on" : "off", "\(title)：\(enabled ? "开启" : "关闭")",
            subtitle, systemImage)
    }

    private static func option(
        _ key: String, _ value: String, _ title: String, _ subtitle: String, _ systemImage: String
    ) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "input.\(key).\(value)", title: title, subtitle: subtitle,
            systemImage: systemImage, keywords: ["input", "输入", key, value, title], group: .settings)
    }

    private static func boolean(_ value: String) -> Bool? {
        switch value {
        case "on": true
        case "off": false
        default: nil
        }
    }
}

enum SoundCommandPreview: Equatable {
    case click(TypingClickSoundStyle)
    case error(TypingErrorSoundStyle)
    case timeWarning
}

enum SoundCommandTarget: Equatable {
    case volume(Double)
    case click(TypingClickSoundStyle?)
    case error(TypingErrorSoundStyle?)
    case timeWarning(TimeWarningOffset)

    var requiresRestart: Bool { false }
    var exitsChallenge: Bool { false }

    var preview: SoundCommandPreview? {
        switch self {
        case .click(let style?): .click(style)
        case .error(let style?): .error(style)
        case .timeWarning(let offset) where offset != .off: .timeWarning
        case .volume, .click(nil), .error(nil), .timeWarning: nil
        }
    }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .volume(let volume):
            settings.soundVolume = volume
        case .click(let style):
            settings.playKeyclickSound = style != nil
            if let style { settings.clickSoundStyle = style }
        case .error(let style):
            settings.playErrorBeep = style != nil
            if let style { settings.errorSoundStyle = style }
        case .timeWarning(let offset):
            settings.timeWarningOffset = offset
        }
    }
}

/// Preserves the fixed reference's sound-option cardinality and command values,
/// while mapping each numbered option to a Typebar-owned native sound.
enum SoundCommandCatalog {
    private static let clickStyles: [TypingClickSoundStyle] = [
        .tink, .pop, .ping, .morse, .ember, .drift, .quartz, .ripple, .reed,
        .pebble, .loom, .orbit, .pulse, .velvet, .copper, .frost, .lantern,
        .meadow, .prism, .rain, .slate, .spark, .tide, .willow, .zephyr, .nocturne,
    ]
    private static let errorStyles: [TypingErrorSoundStyle] = [
        .basso, .funk, .sosumi, .submarine,
    ]
    private static let volumeOptions: [(value: Double, identifier: String, name: String)] = [
        (0.1, "0.1", "轻"), (0.5, "0.5", "中"), (1, "1", "响"),
    ]
    private static let timeWarningOptions: [(value: String, offset: TimeWarningOffset)] = [
        ("off", .off), ("1", .oneSecond), ("3", .threeSeconds),
        ("5", .fiveSeconds), ("10", .tenSeconds),
    ]

    static let items: [CommandPaletteItem] = {
        var result: [CommandPaletteItem] = []
        for option in volumeOptions {
            let identifier = "sound.soundVolume.\(option.identifier)"
            result.append(CommandPaletteItem(
                id: identifier,
                title: "提示音音量：\(option.name)", subtitle: "设为 \(Int(option.value * 100))%",
                systemImage: "speaker.wave.2", keywords: [
                    identifier, "sound", "soundVolume", "volume", "提示音", "音量",
                    option.identifier,
                ], group: .settings))
        }
        result.append(CommandPaletteItem(
            id: "sound.playSoundOnClick.off", title: "键击提示音：关闭",
            subtitle: "保留当前音型供下次开启", systemImage: "speaker.slash",
            keywords: [
                "sound.playSoundOnClick.off", "sound", "playSoundOnClick", "click", "off",
                "键击", "提示音", "关闭",
            ],
            group: .settings))
        for (index, style) in clickStyles.enumerated() {
            let identifier = "sound.playSoundOnClick.\(index + 1)"
            result.append(CommandPaletteItem(
                id: identifier,
                title: "键击提示音：\(style.displayName)", subtitle: "启用 Typebar 原生音型",
                systemImage: "keyboard.badge.ellipsis", keywords: [
                    identifier, "sound", "playSoundOnClick", "click", "键击", "提示音",
                    style.displayName, String(index + 1),
                ], group: .settings))
        }
        result.append(CommandPaletteItem(
            id: "sound.playSoundOnError.off", title: "错误提示音：关闭",
            subtitle: "保留当前音型供下次开启", systemImage: "speaker.slash",
            keywords: [
                "sound.playSoundOnError.off", "sound", "playSoundOnError", "error", "off",
                "错误", "提示音", "关闭",
            ],
            group: .settings))
        for (index, style) in errorStyles.enumerated() {
            let identifier = "sound.playSoundOnError.\(index + 1)"
            result.append(CommandPaletteItem(
                id: identifier,
                title: "错误提示音：\(style.displayName)", subtitle: "启用 macOS 原生音型",
                systemImage: "exclamationmark.triangle", keywords: [
                    identifier, "sound", "playSoundOnError", "error", "错误", "提示音",
                    style.displayName, String(index + 1),
                ], group: .settings))
        }
        for option in timeWarningOptions {
            let identifier = "sound.playTimeWarning.\(option.value)"
            result.append(CommandPaletteItem(
                id: identifier, title: "倒计时提示音：\(option.offset.displayName)",
                subtitle: option.offset == .off ? "关闭结束前提示音" : "启用并试听当前倒计时音型",
                systemImage: option.offset == .off ? "speaker.slash" : "timer",
                keywords: [
                    identifier, "sound", "playTimeWarning", "time", "warning", "倒计时",
                    "提示音", option.value, option.offset.displayName,
                ], group: .settings))
        }
        return result
    }()

    static func target(for identifier: String) -> SoundCommandTarget? {
        if let option = volumeOptions.first(where: {
            identifier == "sound.soundVolume.\($0.identifier)"
        }) {
            return .volume(option.value)
        }
        if identifier == "sound.playSoundOnClick.off" { return .click(nil) }
        if let index = numberedIndex(identifier, prefix: "sound.playSoundOnClick."),
            clickStyles.indices.contains(index)
        {
            return .click(clickStyles[index])
        }
        if identifier == "sound.playSoundOnError.off" { return .error(nil) }
        if let index = numberedIndex(identifier, prefix: "sound.playSoundOnError."),
            errorStyles.indices.contains(index)
        {
            return .error(errorStyles[index])
        }
        if let option = timeWarningOptions.first(where: {
            identifier == "sound.playTimeWarning.\($0.value)"
        }) {
            return .timeWarning(option.offset)
        }
        return nil
    }

    private static func numberedIndex(_ identifier: String, prefix: String) -> Int? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let value = String(identifier.dropFirst(prefix.count))
        guard !value.isEmpty, value.allSatisfy(\.isNumber), let number = Int(value),
            String(number) == value
        else {
            return nil
        }
        return number - 1
    }
}

enum CaretCommandTarget: Equatable {
    case smooth(SmoothCaretMotion)
    case primary(TypingCaretStyle)
    case pace(TypingCaretStyle)
    case repeatedPace(Bool)

    var requiresRestart: Bool { false }
    var exitsChallenge: Bool { false }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .smooth(let motion): settings.smoothCaretMotion = motion
        case .primary(let style): settings.caretStyle = style
        case .pace(let style): settings.paceCaretStyle = style
        case .repeatedPace(let enabled): settings.repeatedPace = enabled
        }
    }
}

/// Uses the fixed schema values while keeping all caret rendering native.
enum CaretCommandCatalog {
    private static let motionOptions: [(value: String, motion: SmoothCaretMotion)] = [
        ("off", .off), ("slow", .slow), ("medium", .medium), ("fast", .fast),
    ]
    private static let styleOptions: [(value: String, style: TypingCaretStyle)] = [
        ("off", .off), ("default", .bar), ("block", .block), ("outline", .outline),
        ("underline", .underline), ("carrot", .carrot), ("banana", .banana),
        ("monkey", .monkey),
    ]

    static let items: [CommandPaletteItem] = {
        var result: [CommandPaletteItem] = []
        for option in motionOptions {
            let identifier = "caret.smoothCaret.\(option.value)"
            result.append(CommandPaletteItem(
                id: identifier, title: "平滑光标：\(option.motion.displayName)",
                subtitle: "立即更新字符间移动方式", systemImage: "character.cursor.ibeam",
                keywords: [
                    identifier, "caret", "smoothCaret", "smooth", "光标", "平滑",
                    option.value, option.motion.displayName,
                ], group: .settings))
        }
        appendStyleItems(
            to: &result, key: "caretStyle", title: "光标样式", target: "主光标")
        appendStyleItems(
            to: &result, key: "paceCaretStyle", title: "节奏光标样式", target: "节奏光标")
        for enabled in [false, true] {
            let value = enabled ? "on" : "off"
            let identifier = "caret.repeatedPace.\(value)"
            result.append(CommandPaletteItem(
                id: identifier, title: "重开沿用上一轮节奏：\(enabled ? "开启" : "关闭")",
                subtitle: enabled ? "重开后使用上一轮速度一次" : "重开后不自动沿用上一轮速度",
                systemImage: enabled ? "repeat.circle.fill" : "repeat.circle",
                keywords: [
                    identifier, "caret", "repeatedPace", "repeat", "重开", "节奏", value,
                ], group: .settings))
        }
        return result
    }()

    static func target(for identifier: String) -> CaretCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "caret" else { return nil }
        let key = String(parts[1])
        let value = String(parts[2])
        switch key {
        case "smoothCaret":
            return motionOptions.first(where: { $0.value == value }).map {
                .smooth($0.motion)
            }
        case "caretStyle":
            return styleOptions.first(where: { $0.value == value }).map {
                .primary($0.style)
            }
        case "paceCaretStyle":
            return styleOptions.first(where: { $0.value == value }).map {
                .pace($0.style)
            }
        case "repeatedPace":
            if value == "off" { return .repeatedPace(false) }
            if value == "on" { return .repeatedPace(true) }
            return nil
        default:
            return nil
        }
    }

    private static func appendStyleItems(
        to result: inout [CommandPaletteItem], key: String, title: String, target: String
    ) {
        for option in styleOptions {
            let identifier = "caret.\(key).\(option.value)"
            result.append(CommandPaletteItem(
                id: identifier, title: "\(title)：\(option.style.displayName)",
                subtitle: "立即更新\(target)的原生绘制样式", systemImage: "cursorarrow.motionlines",
                keywords: [
                    identifier, "caret", key, "style", "光标", option.value,
                    option.style.displayName,
                ], group: .settings))
        }
    }
}

enum PaceCaretCommandTarget: Equatable {
    case mode(PaceGuideMode)
    case customSpeed

    var requiresRestart: Bool { true }
    var exitsChallenge: Bool { true }

    @MainActor
    func apply(to settings: AppSettings) {
        guard case .mode(let mode) = self else { return }
        settings.paceGuideMode = mode
    }
}

/// Preserves the fixed reference command values while mapping them to
/// Typebar-owned pace modes and native result storage.
enum PaceCaretCommandCatalog {
    private static let options: [(value: String, target: PaceCaretCommandTarget, title: String)] = [
        ("off", .mode(.off), "关闭"),
        ("pb", .mode(.personalBest), "同类个人最佳"),
        ("tagPb", .mode(.activeTagPersonalBest), "活动标签个人最佳"),
        ("last", .mode(.lastTest), "上一轮速度"),
        ("average", .mode(.recentAverage), "最近 10 次同类平均"),
        ("daily", .mode(.dailyBest), "过去 24 小时同类最佳"),
        ("custom", .customSpeed, "自定义速度…"),
    ]

    static let items = options.map { option in
        let identifier = "caret.paceCaret.\(option.value)"
        return CommandPaletteItem(
            id: identifier, title: "节奏引导：\(option.title)",
            subtitle: option.target == .customSpeed ? "输入目标速度并立即重开" : "切换目标来源并立即重开",
            systemImage: option.target == .customSpeed ? "metronome.fill" : "metronome",
            keywords: [
                identifier, "caret", "paceCaret", "pace", "节奏", "目标", option.value,
                option.title,
            ], group: .settings)
    }

    static func target(for identifier: String) -> PaceCaretCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "caret", parts[1] == "paceCaret" else { return nil }
        let value = String(parts[2])
        return options.first(where: { $0.value == value })?.target
    }
}

enum AppearanceCommandTarget: Equatable {
    case progress(LiveProgressStyle)
    case speed(LiveMetricStyle)
    case accuracy(LiveMetricStyle)
    case burst(LiveMetricStyle)
    case color(LiveStatsColor)
    case opacity(LiveStatsOpacity)
    case highlight(PromptHighlightMode)
    case typedEffect(TypedCharacterEffect)
    case tape(PracticeTapeMode)
    case smoothLineScroll(Bool)
    case showAllLines(Bool)
    case speedUnit(TypingSpeedUnit)
    case alwaysShowDecimalPlaces(Bool)
    case startGraphsAtZero(Bool)

    var requiresRestart: Bool { false }

    var exitsChallenge: Bool {
        switch self {
        case .highlight, .showAllLines: true
        default: false
        }
    }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .progress(let style): settings.liveProgressStyle = style
        case .speed(let style): settings.liveSpeedStyle = style
        case .accuracy(let style): settings.liveAccuracyStyle = style
        case .burst(let style): settings.liveBurstStyle = style
        case .color(let color): settings.liveStatsColor = color
        case .opacity(let opacity): settings.liveStatsOpacity = opacity
        case .highlight(let mode): settings.promptHighlightMode = mode
        case .typedEffect(let effect): settings.typedCharacterEffect = effect
        case .tape(let mode): settings.practiceTapeMode = mode
        case .smoothLineScroll(let enabled): settings.smoothPracticeLineScroll = enabled
        case .showAllLines(let enabled): settings.showAllPracticeLines = enabled
        case .speedUnit(let unit): settings.typingSpeedUnit = unit
        case .alwaysShowDecimalPlaces(let enabled): settings.alwaysShowDecimalPlaces = enabled
        case .startGraphsAtZero(let enabled): settings.startGraphsAtZero = enabled
        }
    }
}

/// Exposes the fixed reference's discrete appearance commands through
/// Typebar's existing native presentation settings.
enum AppearanceCommandCatalog {
    private struct Option {
        let key: String
        let value: String
        let setting: String
        let choice: String
        let target: AppearanceCommandTarget
    }

    private static let options: [Option] = {
        var result: [Option] = []
        result += progressOptions.map {
            Option(key: "timerStyle", value: $0.0, setting: "实时进度", choice: $0.1.displayName,
                   target: .progress($0.1))
        }
        for (key, setting, target) in [
            ("liveSpeedStyle", "实时速度", { AppearanceCommandTarget.speed($0) }),
            ("liveAccStyle", "实时准确率", { AppearanceCommandTarget.accuracy($0) }),
            ("liveBurstStyle", "实时 Burst", { AppearanceCommandTarget.burst($0) }),
        ] {
            result += metricOptions.map {
                Option(key: key, value: $0.0, setting: setting, choice: $0.1.displayName,
                       target: target($0.1))
            }
        }
        result += colorOptions.map {
            Option(key: "timerColor", value: $0.0, setting: "实时指标颜色",
                   choice: $0.1.displayName, target: .color($0.1))
        }
        result += opacityOptions.map {
            Option(key: "timerOpacity", value: $0.0, setting: "实时指标透明度",
                   choice: $0.1.displayName, target: .opacity($0.1))
        }
        result += highlightOptions.map {
            Option(key: "highlightMode", value: $0.0, setting: "提示高亮",
                   choice: $0.1.displayName, target: .highlight($0.1))
        }
        result += TypedCharacterEffect.allCases.map {
            Option(key: "typedEffect", value: $0.rawValue, setting: "已输入字符效果",
                   choice: $0.displayName, target: .typedEffect($0))
        }
        result += tapeOptions.map {
            Option(key: "tapeMode", value: $0.0, setting: "单行卷带",
                   choice: $0.1.displayName, target: .tape($0.1))
        }
        result += booleanOptions(
            key: "smoothLineScroll", setting: "平滑卷带滚动",
            target: AppearanceCommandTarget.smoothLineScroll)
        result += booleanOptions(
            key: "showAllLines", setting: "显示完整提示行",
            target: AppearanceCommandTarget.showAllLines)
        result += speedUnitOptions.map {
            Option(key: "typingSpeedUnit", value: $0.rawValue, setting: "速度单位",
                   choice: $0.displayName, target: .speedUnit($0))
        }
        result += booleanOptions(
            key: "alwaysShowDecimalPlaces", setting: "结果固定两位小数",
            target: AppearanceCommandTarget.alwaysShowDecimalPlaces)
        result += booleanOptions(
            key: "startGraphsAtZero", setting: "图表从零开始",
            target: AppearanceCommandTarget.startGraphsAtZero)
        return result
    }()

    static let items = options.map { option in
        let identifier = "appearance.\(option.key).\(option.value)"
        return CommandPaletteItem(
            id: identifier, title: "\(option.setting)：\(option.choice)",
            subtitle: "立即更新原生显示，不重新生成练习", systemImage: "textformat.size",
            keywords: [
                identifier, "appearance", "display", "显示", option.key, option.value,
                option.setting, option.choice,
            ], group: .settings)
    }

    static func target(for identifier: String) -> AppearanceCommandTarget? {
        options.first {
            "appearance.\($0.key).\($0.value)" == identifier
        }?.target
    }

    private static let progressOptions: [(String, LiveProgressStyle)] = [
        ("off", .off), ("bar", .bar), ("text", .text), ("mini", .mini),
        ("flash_text", .flashText), ("flash_mini", .flashMini),
    ]
    private static let metricOptions: [(String, LiveMetricStyle)] = [
        ("off", .off), ("text", .text), ("mini", .mini),
    ]
    private static let colorOptions: [(String, LiveStatsColor)] = [
        ("black", .black), ("sub", .secondary), ("text", .primary), ("main", .accent),
    ]
    private static let opacityOptions: [(String, LiveStatsOpacity)] = [
        ("0.25", .quarter), ("0.5", .half), ("0.75", .threeQuarters), ("1", .full),
    ]
    private static let highlightOptions: [(String, PromptHighlightMode)] = [
        ("off", .off), ("letter", .letter), ("word", .word), ("next_word", .nextWord),
        ("next_two_words", .nextTwoWords), ("next_three_words", .nextThreeWords),
    ]
    private static let tapeOptions: [(String, PracticeTapeMode)] = [
        ("off", .off), ("letter", .letter), ("word", .word),
    ]
    private static let speedUnitOptions: [TypingSpeedUnit] = [.wpm, .cpm, .wps, .cps]

    private static func booleanOptions(
        key: String,
        setting: String,
        target: (Bool) -> AppearanceCommandTarget
    ) -> [Option] {
        [
            Option(key: key, value: "off", setting: setting, choice: "关闭", target: target(false)),
            Option(key: key, value: "on", setting: setting, choice: "开启", target: target(true)),
        ]
    }
}

enum KeyboardGuideCommandTarget: Equatable {
    case mode(KeyboardGuideMode)
    case style(KeyboardGuideStyle)
    case legend(KeyboardGuideLegendStyle)
    case keys(KeyboardGuideKeysMode)

    var requiresRestart: Bool { false }

    var exitsChallenge: Bool {
        if case .mode = self { return true }
        return false
    }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .mode(let mode): settings.keyboardGuideMode = mode
        case .style(let style): settings.keyboardGuideStyle = style
        case .legend(let legend): settings.keyboardGuideLegendStyle = legend
        case .keys(let keys): settings.keyboardGuideKeysMode = keys
        }
    }
}

/// Preserves the fixed reference's discrete visual-keyboard values while
/// applying them only to Typebar's presentation settings.
enum KeyboardGuideCommandCatalog {
    private struct Option {
        let key: String
        let value: String
        let setting: String
        let choice: String
        let target: KeyboardGuideCommandTarget
    }

    private static let options: [Option] =
        KeyboardGuideMode.allCases.map {
            Option(
                key: "keymapMode", value: $0.rawValue, setting: "键盘提示模式",
                choice: $0.displayName, target: .mode($0))
        }
        + KeyboardGuideStyle.allCases.map {
            Option(
                key: "keymapStyle", value: $0.rawValue, setting: "键盘样式",
                choice: $0.displayName, target: .style($0))
        }
        + KeyboardGuideLegendStyle.allCases.map {
            Option(
                key: "keymapLegendStyle", value: $0.rawValue, setting: "键盘图例",
                choice: $0.displayName, target: .legend($0))
        }
        + KeyboardGuideKeysMode.allCases.map {
            Option(
                key: "keymapKeys", value: $0.rawValue, setting: "键盘按键",
                choice: $0.displayName, target: .keys($0))
        }

    static let items = options.map { option in
        let identifier = "keyboard.\(option.key).\(option.value)"
        return CommandPaletteItem(
            id: identifier, title: "\(option.setting)：\(option.choice)",
            subtitle: "立即更新原生屏幕键盘", systemImage: "keyboard",
            keywords: [
                identifier, "keyboard", "keymap", "键盘", option.key, option.value,
                option.setting, option.choice,
            ], group: .settings)
    }

    static func target(for identifier: String) -> KeyboardGuideCommandTarget? {
        options.first { "keyboard.\($0.key).\($0.value)" == identifier }?.target
    }
}

enum KeyboardGuideSizeCommand {
    static let item = CommandPaletteItem(
        id: "keyboard.keymapSize", title: "键盘提示大小…",
        subtitle: "输入 0.5–3.5 倍，步长 0.1", systemImage: "arrow.up.left.and.arrow.down.right",
        keywords: ["keyboard", "keymap", "keymapSize", "键盘", "大小", "缩放"],
        group: .settings)
}

enum KeyboardGuideLayoutCommandTarget: Equatable {
    case inputSync
    case builtIn(KeyboardLayout)

    var requiresRestart: Bool { true }
    var exitsChallenge: Bool { true }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .inputSync:
            settings.keyboardGuideLayoutSource = .inputEmulation
        case .builtIn(let layout):
            settings.keyboardLayout = layout
            settings.keyboardGuideLayoutSource = .builtIn
        }
    }
}

/// Reuses the independently audited official layout-name mapping but routes
/// selections to the visual guide rather than the physical input bridge.
enum KeyboardGuideLayoutCommandCatalog {
    private static let inputPrefix = "input.layout."
    private static let keymapPrefix = "keyboard.keymapLayout."

    static let items: [CommandPaletteItem] = {
        let sync = CommandPaletteItem(
            id: "\(keymapPrefix)overrideSync", title: "键盘图布局：跟随输入模拟",
            subtitle: "持续同步输入布局并立即重开", systemImage: "keyboard.badge.ellipsis",
            keywords: [
                "\(keymapPrefix)overrideSync", "keyboard", "keymap", "keymapLayout",
                "overrideSync", "default", "emulator sync",
                "键盘", "布局", "跟随", "同步",
            ], group: .settings)
        let layouts = OfficialLayoutCommandCatalog.items.dropFirst().map { item in
            let officialName = String(item.id.dropFirst(inputPrefix.count))
            let identifier = "\(keymapPrefix)\(officialName)"
            return CommandPaletteItem(
                id: identifier,
                title: item.title.replacingOccurrences(of: "模拟布局：", with: "键盘图布局："),
                subtitle: "只切换屏幕键盘并立即重开", systemImage: "keyboard.fill",
                keywords: item.keywords
                    + [identifier, "keyboard", "keymap", "keymapLayout", officialName],
                group: .settings)
        }
        return [sync] + layouts
    }()

    static func target(for identifier: String) -> KeyboardGuideLayoutCommandTarget? {
        guard identifier.hasPrefix(keymapPrefix) else { return nil }
        let officialName = String(identifier.dropFirst(keymapPrefix.count))
        guard !officialName.isEmpty, !officialName.contains(".") else { return nil }
        if officialName == "overrideSync" { return .inputSync }
        guard
            case .builtIn(let layout) = OfficialLayoutCommandCatalog.target(
                for: "\(inputPrefix)\(officialName)")
        else { return nil }
        return .builtIn(layout)
    }
}

enum OfficialLayoutCommandTarget: Equatable {
    case system
    case builtIn(KeyboardLayout)

    var requiresRestart: Bool { true }
    var exitsChallenge: Bool { true }

    @MainActor
    func apply(to settings: AppSettings) {
        switch self {
        case .system: settings.keyboardInputLayout = .system
        case .builtIn(let layout): settings.keyboardInputLayout = .init(emulating: layout)
        }
    }
}

/// Exposes only the fixed reference layout schema. Five additional Typebar
/// layouts remain available in Settings without masquerading as reference
/// command choices.
enum OfficialLayoutCommandCatalog {
    private static let typebarOnlyLayouts: Set<KeyboardLayout> = [
        .nordicQwerty, .hungarianQwertz, .greekAlphabetic, .bulgarianCyrillic,
        .serbianCyrillic,
    ]

    private static let aliases: [String: KeyboardLayout] = [
        "qwerty": .ansiQwerty,
        "dvorak": .ansiDvorak,
        "dvorak_L": .dvorakLeft,
        "dvorak_R": .dvorakRight,
        "colemak": .ansiColemak,
        "colemak_angle": .ansiColemakAngle,
        "colemak_wide": .ansiColemakWide,
        "colemak_dh": .ansiColemakDH,
        "colemak_dhv": .ansiColemakDHV,
        "colemak_dh_iso": .colemakDHISO,
        "colemak_dh_wide": .colemakDHWideANSI,
        "colemak_dh_iso_wide": .colemakDHWideISO,
        "colemak_dh_matrix": .colemakDHMatrix,
        "colemak_dhk": .colemakDHKANSI,
        "colemak_dhk_iso": .colemakDHKISO,
        "MTGAP_ASRT": .mtgapASRT,
        "QGMLWB": .qgmlwb,
        "QGMLWY": .qgmlwy,
        "prog_dvorak": .programmerDvorak,
        "prog_dvorak_prime": .programmerDvorakPrime,
        "german_dvorak": .germanDvorak,
        "german_dvorak_imp": .germanDvorakImproved,
        "spanish_dvorak": .spanishDvorak,
        "swedish_colemak": .swedishColemak,
        "swedish_dvorak": .swedishDvorak,
        "dvorak_fr": .frenchDvorak,
        "azerty_AFNOR": .frenchAzertyAFNOR,
        "bepo": .frenchBepo,
        "bepo_AFNOR": .frenchBepoAFNOR,
        "alpha": .ansiAlpha,
        "handsdown": .ansiHandsDown,
        "handsdown_alt": .ansiHandsDownAlt,
        "handsdown_neu": .ansiHandsDownNeu,
        "handsdown_neu_inverted": .ansiHandsDownNeuInverted,
        "MTGAP": .mtgap,
        "MTGAP_full": .mtgapFull,
        "ISRT": .isrt,
        "ISRT_Angle": .isrtAngle,
        "semimak_jq": .semimakJQ,
        "semimak_jqc": .semimakJQC,
        "canary_matrix": .canaryMatrix,
        "boo_mangle": .booMangle,
        "APT": .apt,
        "APT_angle": .aptAngle,
        "middlemak-nh": .middlemakNH,
        "Foalmak": .foalmak,
        "ARTS": .arts,
        "capewell_dvorak": .capewellDvorak,
        "qwertz": .germanQwertz,
        "swiss_german": .swissGerman,
        "swiss_french": .swissFrench,
        "workman": .ansiWorkman,
        "prog_workman": .programmerWorkman,
        "norman": .ansiNorman,
        "turkish_q": .turkishQ,
        "turkish_f": .turkishF,
        "turkish_e": .turkishE,
        "uk_qwerty": .ukQwerty,
        "spanish_qwerty": .spanishQwerty,
        "italian_qwerty": .italianQwerty,
        "latam_qwerty": .latinAmericanQwerty,
        "azerty": .frenchAzerty,
        "persian_standard": .persianStandard,
        "persian_farsi": .persianFarsi,
        "arabic_101": .arabic101,
        "arabic_102": .arabic102,
        "arabic_mac": .arabicMac,
        "urdu_phonetic": .urduPhonetic,
        "thai_kedmanee": .thaiKedmanee,
        "thai_pattachote": .thaiPattachote,
        "japanese_hiragana": .japaneseHiragana,
        "hindi_inscript": .hindiInscript,
        "armenian_hm_qwerty": .armenianHMQwerty,
        "mongolian": .mongolianCyrillic,
        "polish_programmers": .polishProgrammers,
        "bulgarian_phonetic_traditional": .bulgarianPhoneticTraditional,
        "ukrainian": .ukrainianJcuken,
        "russian": .russianJcuken,
        "norwegian_qwerty": .norwegianQwerty,
        "portuguese_pt_qwerty_iso": .portugueseQwertyISO,
        "portuguese_pt_qwerty_ansi": .portugueseQwertyANSI,
        "ABNT2": .brazilianABNT2,
        "swedish_qwerty": .swedishQwerty,
        "danish_qwerty": .danishQwerty,
        "hungarian": .hungarianOfficial,
        "JCUKEN": .jcuken,
        "bulgarian": .bulgarianOfficial,
    ]

    private static let officialNameByLayout = Dictionary(
        uniqueKeysWithValues: aliases.map { ($0.value, $0.key) })

    static let items: [CommandPaletteItem] = {
        let disabled = CommandPaletteItem(
            id: "input.layout.default", title: "输入布局模拟：关闭",
            subtitle: "使用 macOS 当前输入源", systemImage: "keyboard",
            keywords: [
                "input", "layout", "default", "输入", "布局", "关闭", "系统当前输入源",
            ], group: .settings)
        let layouts = KeyboardLayout.allCases.compactMap { layout -> CommandPaletteItem? in
            guard !typebarOnlyLayouts.contains(layout) else { return nil }
            let officialName = officialNameByLayout[layout] ?? layout.rawValue
            return CommandPaletteItem(
                id: "input.layout.\(officialName)", title: "模拟布局：\(layout.displayName)",
                subtitle: "按此布局解释物理按键并立即重开", systemImage: "keyboard.fill",
                keywords: ["input", "layout", "输入", "布局", officialName, layout.displayName],
                group: .settings)
        }
        return [disabled] + layouts
    }()

    static func target(for identifier: String) -> OfficialLayoutCommandTarget? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "input", parts[1] == "layout" else { return nil }
        let officialName = String(parts[2])
        if officialName == "default" { return .system }
        if let layout = aliases[officialName] { return .builtIn(layout) }
        guard let layout = KeyboardLayout(rawValue: officialName),
            !typebarOnlyLayouts.contains(layout)
        else { return nil }
        return .builtIn(layout)
    }
}

enum TestConfigurationCommandChallengePolicy {
    private static let modeIdentifiers: Set<String> = [
        "mode.time", "mode.words", "mode.quote", "mode.zen", "mode.custom",
    ]

    static func exitsChallenge(for identifier: String) -> Bool {
        modeIdentifiers.contains(identifier)
            || QuickTestParameterCommandCatalog.target(for: identifier) != nil
            || QuoteCommandCatalog.target(for: identifier) != nil
            || LanguageCommandCatalog.target(for: identifier) != nil
            || PracticePreferenceCommandCatalog.target(for: identifier)?.exitsChallenge == true
            || InputRuleCommandCatalog.target(for: identifier)?.exitsChallenge == true
            || OfficialLayoutCommandCatalog.target(for: identifier)?.exitsChallenge == true
            || PaceCaretCommandCatalog.target(for: identifier)?.exitsChallenge == true
            || AppearanceCommandCatalog.target(for: identifier)?.exitsChallenge == true
            || KeyboardGuideCommandCatalog.target(for: identifier)?.exitsChallenge == true
            || KeyboardGuideLayoutCommandCatalog.target(for: identifier)?.exitsChallenge == true
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
