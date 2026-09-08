import Foundation

enum SettingsSearch {
    struct Entry: Equatable, Identifiable {
        let id: String
        let title: String
        let section: Section
        let keywords: [String]

        init(_ id: String, _ title: String, section: Section, keywords: String = "") {
            self.id = id
            self.title = title
            self.section = section
            self.keywords = keywords.split(separator: "|").map(String.init)
        }
    }

    enum Section: String, CaseIterable {
        case test
        case display
        case customTheme
        case system
        case account
        case moderation
        case defaults

        var displayName: String {
            switch self {
            case .test: "测试"
            case .display: "显示"
            case .customTheme: "自定义主题"
            case .system: "系统"
            case .account: "自建账户"
            case .moderation: "审核"
            case .defaults: "恢复默认设置"
            }
        }
    }

    static let preferenceCatalog: [Entry] = [
        Entry("difficulty", "难度", section: .test, keywords: "difficulty|普通|专家"),
        Entry("strictSpace", "严格空格", section: .test, keywords: "strict space"),
        Entry("stopOnError", "遇错停下", section: .test, keywords: "stop on error"),
        Entry("deleteOnError", "遇错删除", section: .test, keywords: "delete on error"),
        Entry("hideExtraLetters", "隐藏额外字符", section: .test, keywords: "hide extra letters"),
        Entry("blindMode", "盲打", section: .test, keywords: "blind mode"),
        Entry("quickRestart", "快速重开按键", section: .test, keywords: "quick restart"),
        Entry("keyTips", "显示快捷键提示", section: .test, keywords: "key tips|shortcuts"),
        Entry("commandPalette", "命令面板浏览", section: .test, keywords: "command palette"),
        Entry("saveResults", "保存完成成绩", section: .test, keywords: "save results"),
        Entry("wordsHistory", "完成后自动展开单词历史", section: .test, keywords: "words history"),
        Entry("burstHeatmap", "结果页显示单词 Burst 热力图", section: .test, keywords: "burst heatmap"),
        Entry("focusWarning", "输入框失焦提示", section: .test, keywords: "focus warning"),
        Entry("capsLockWarning", "大写锁定提示", section: .test, keywords: "caps lock warning"),
        Entry("errorSound", "错误提示音", section: .test, keywords: "error sound|beep"),
        Entry("keyclickSound", "键击提示音", section: .test, keywords: "keyclick sound"),
        Entry("timeWarning", "倒计时提示音", section: .test, keywords: "time warning sound"),
        Entry("soundVolume", "提示音音量", section: .test, keywords: "sound volume"),
        Entry("freedomMode", "自由回退", section: .test, keywords: "freedom mode"),
        Entry("confidenceMode", "信心模式", section: .test, keywords: "confidence mode"),
        Entry("oppositeShift", "反向 Shift", section: .test, keywords: "opposite shift"),
        Entry("codeUnindent", "代码退格反缩进", section: .test, keywords: "code unindent backspace"),
        Entry("minimumAccuracy", "最低准确率", section: .test, keywords: "minimum accuracy"),
        Entry("minimumWpm", "最低整体速度", section: .test, keywords: "minimum wpm"),
        Entry("minimumBurst", "最低单词速度", section: .test, keywords: "minimum word burst"),
        Entry("quickEnd", "最后一词快速结束", section: .test, keywords: "quick end"),
        Entry("englishVariant", "英文拼写", section: .test, keywords: "english variant"),
        Entry("lazyMode", "简化输入", section: .test, keywords: "lazy mode|重音|变音|连字"),
        Entry("modifiers", "趣味修饰器", section: .test, keywords: "funbox|modifier"),

        Entry("theme", "主题", section: .display, keywords: "theme"),
        Entry("systemTheme", "跟随 macOS 深浅色自动切换", section: .display, keywords: "system theme|light dark"),
        Entry("randomTheme", "完成后随机主题", section: .display, keywords: "random theme"),
        Entry("flipColors", "翻转已输入与后续文本颜色", section: .display, keywords: "flip test colors"),
        Entry("colorful", "彩色测试文字", section: .display, keywords: "colorful mode"),
        Entry("background", "背景图片", section: .display, keywords: "custom background image url"),
        Entry("backgroundFilter", "背景图片滤镜", section: .display, keywords: "blur brightness saturation opacity"),
        Entry("backdrop", "练习背景", section: .display, keywords: "practice backdrop"),
        Entry("companion", "显示节奏伙伴", section: .display, keywords: "typing companion"),
        Entry("typingPower", "键入能量效果", section: .display, keywords: "typing power"),
        Entry("fontSize", "练习字体大小", section: .display, keywords: "font size"),
        Entry("font", "练习字体", section: .display, keywords: "font family|local font"),
        Entry("lineWidth", "练习行宽", section: .display, keywords: "line width"),
        Entry("tapeMode", "单行卷带", section: .display, keywords: "tape mode"),
        Entry("allLines", "显示完整提示行", section: .display, keywords: "show all lines"),
        Entry("smoothCaret", "平滑光标", section: .display, keywords: "smooth caret"),
        Entry("caretStyle", "光标样式", section: .display, keywords: "caret style"),
        Entry("typoIndicator", "错误字符显示", section: .display, keywords: "typo indicator"),
        Entry("composition", "组合输入显示", section: .display, keywords: "composition ime"),
        Entry("speedUnit", "速度单位", section: .display, keywords: "typing speed unit wpm cpm"),
        Entry("average", "显示近 10 次平均", section: .display, keywords: "average"),
        Entry("personalBest", "显示本机个人最佳", section: .display, keywords: "personal best pb"),
        Entry("decimals", "结果页固定显示两位小数", section: .display, keywords: "decimal places"),
        Entry("graphZero", "速度图从零开始", section: .display, keywords: "start graphs at zero"),
        Entry("streakBoundary", "连续练习日分界", section: .display, keywords: "streak day boundary"),
        Entry("typedEffect", "已输入字符效果", section: .display, keywords: "typed character effect"),
        Entry("liveSpeed", "实时速度显示", section: .display, keywords: "live speed wpm"),
        Entry("liveAccuracy", "实时准确率显示", section: .display, keywords: "live accuracy"),
        Entry("liveBurst", "实时 Burst 显示", section: .display, keywords: "live burst"),
        Entry("liveProgress", "实时进度显示", section: .display, keywords: "live progress"),
        Entry("liveStatsColor", "实时指标颜色", section: .display, keywords: "live stats color"),
        Entry("liveStatsOpacity", "实时指标透明度", section: .display, keywords: "live stats opacity"),
        Entry("promptHighlight", "提示高亮范围", section: .display, keywords: "highlight mode"),
        Entry("paceGuide", "节奏引导", section: .display, keywords: "pace guide"),
        Entry("keyboardGuide", "键盘提示模式", section: .display, keywords: "keyboard guide"),
        Entry("keyboardLayout", "键盘图来源与布局", section: .display, keywords: "keyboard layout keymap"),
        Entry("inputLayout", "输入布局模拟", section: .display, keywords: "input layout emulation"),

        Entry("customTheme", "创建、编辑与删除自定义主题", section: .customTheme, keywords: "custom theme colors"),
        Entry("globalHotkey", "启用全局唤起", section: .system, keywords: "global hotkey accessibility"),
        Entry("serviceEndpoint", "账户服务地址", section: .account, keywords: "server endpoint account"),
        Entry("accountIdentity", "登录、注册与邮箱验证", section: .account, keywords: "login register email verification"),
        Entry("publicProfile", "公开资料", section: .account, keywords: "public profile badge bio"),
        Entry("developerKey", "开发者访问密钥", section: .account, keywords: "developer access key"),
        Entry("remoteResults", "服务端成绩", section: .account, keywords: "remote results sync"),
        Entry("linkedAccounts", "第三方登录关联", section: .account, keywords: "oauth github google discord"),
        Entry("accountSecurity", "邮箱、密码与设备会话", section: .account, keywords: "password security sessions"),
        Entry("quoteSubmission", "引语投稿", section: .account, keywords: "quote submission"),
        Entry("moderation", "引语、资料与公告审核", section: .moderation, keywords: "moderation announcement"),
        Entry("defaults", "恢复默认设置", section: .defaults, keywords: "restore reset defaults"),
    ]

    static func matches(query: String, terms: [String]) -> Bool {
        let tokens = normalized(query).split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        let searchable = terms.map(normalized).joined(separator: " ")
        return tokens.allSatisfy { searchable.contains($0) }
    }

    static func results(query: String, entries: [Entry] = preferenceCatalog) -> [Entry] {
        let tokens = normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }

        let scored = entries.map { entry in
            let searchable = ([entry.title, entry.section.displayName] + entry.keywords)
                .map(normalized)
                .joined(separator: " ")
            return (entry, tokens.reduce(0) { $0 + (searchable.contains($1) ? 1 : 0) })
        }
        let bestScore = scored.map(\.1).max() ?? 0
        guard bestScore > 0 else { return [] }
        return scored.filter { $0.1 == bestScore }.map(\.0)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
