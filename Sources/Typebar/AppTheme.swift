import AppKit
import SwiftUI

struct ThemeColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(color: Color) {
        let components = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(components.redComponent)
        green = Double(components.greenComponent)
        blue = Double(components.blueComponent)
        opacity = Double(components.alphaComponent)
    }

    var color: Color { Color(red: red, green: green, blue: blue, opacity: opacity) }
}

struct ResolvedTheme: Equatable {
    let background: Color
    let panel: Color
    let accent: Color
    let text: Color
    let secondaryText: Color
    let caret: Color
    let fadedText: Color
    let error: Color
    let extraInput: Color
    let colorfulError: Color
    let colorfulExtraInput: Color
    let colorScheme: ColorScheme

    init(
        background: Color, panel: Color, accent: Color, colorScheme: ColorScheme,
        text: Color? = nil, secondaryText: Color? = nil, error: Color? = nil,
        extraInput: Color? = nil, caret: Color? = nil, fadedText: Color? = nil,
        colorfulError: Color? = nil, colorfulExtraInput: Color? = nil
    ) {
        self.background = background
        self.panel = panel
        self.accent = accent
        self.colorScheme = colorScheme
        self.text = text ?? Self.defaultTextColor(for: colorScheme)
        self.secondaryText = secondaryText ?? Self.defaultSecondaryTextColor(for: colorScheme)
        self.error = error ?? Self.defaultErrorColor
        self.extraInput = extraInput ?? Self.defaultErrorColor
        self.caret = caret ?? accent
        self.fadedText = fadedText ?? self.secondaryText
        self.colorfulError = colorfulError ?? self.error
        self.colorfulExtraInput = colorfulExtraInput ?? self.extraInput
    }

    static func defaultTextColor(for colorScheme: ColorScheme) -> Color {
        Color(white: colorScheme == .dark ? 0.94 : 0.12)
    }

    static func defaultSecondaryTextColor(for colorScheme: ColorScheme) -> Color {
        Color(white: colorScheme == .dark ? 0.68 : 0.38)
    }

    static var defaultErrorColor: Color { .red }

    func errorColor(usesColorfulMode: Bool) -> Color {
        usesColorfulMode ? colorfulError : error
    }

    func extraInputColor(usesColorfulMode: Bool) -> Color {
        usesColorfulMode ? colorfulExtraInput : extraInput
    }
}

/// Original, code-drawn practice backgrounds. These intentionally avoid image
/// assets so the visual treatment stays local to Typebar and theme-aware.
enum PracticeBackdropStyle: String, CaseIterable, Codable, Equatable, Identifiable {
    case solid
    case halos
    case grid

    var id: Self { self }

    func requiresTimeline(reduceMotion: Bool, systemReduceMotion: Bool) -> Bool {
        self == .halos && !reduceMotion && !systemReduceMotion
    }

    var displayName: String {
        switch self {
        case .solid: "纯色"
        case .halos: "光晕"
        case .grid: "网格"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .solid: "纯色背景"
        case .halos: "缓慢移动的主题色光晕"
        case .grid: "主题色细网格"
        }
    }
}

struct PracticeBackdrop: View {
    let style: PracticeBackdropStyle
    let theme: ResolvedTheme
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

    var body: some View {
        Group {
            if style.requiresTimeline(reduceMotion: reduceMotion, systemReduceMotion: systemReduceMotion) {
                TimelineView(
                    .animation(minimumInterval: AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate))
                ) { timeline in
                    content(phase: sin(timeline.date.timeIntervalSinceReferenceDate / 4))
                }
            } else {
                content(phase: 0)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func content(phase: Double) -> some View {
        GeometryReader { proxy in
            ZStack {
                theme.background
                switch style {
                case .solid:
                    EmptyView()
                case .halos:
                    haloLayer(size: proxy.size, phase: phase)
                case .grid:
                    gridLayer(size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func haloLayer(size: CGSize, phase: Double) -> some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(0.18))
                .frame(width: max(size.width, size.height) * 0.78)
                .blur(radius: 44)
                .offset(x: size.width * (0.23 + 0.08 * phase), y: -size.height * 0.22)
            Circle()
                .fill(theme.panel.opacity(0.76))
                .frame(width: max(size.width, size.height) * 0.62)
                .blur(radius: 52)
                .offset(x: -size.width * (0.28 + 0.06 * phase), y: size.height * 0.28)
        }
    }

    private func gridLayer(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 34
            let color = theme.accent.opacity(0.10)
            for x in stride(from: 0, through: canvasSize.width, by: spacing) {
                context.stroke(Path(CGRect(x: x, y: 0, width: 0, height: canvasSize.height)), with: .color(color), lineWidth: 0.5)
            }
            for y in stride(from: 0, through: canvasSize.height, by: spacing) {
                context.stroke(Path(CGRect(x: 0, y: y, width: canvasSize.width, height: 0)), with: .color(color), lineWidth: 0.5)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct CustomThemeDefinition: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var background: ThemeColor
    var panel: ThemeColor
    var accent: ThemeColor
    var text: ThemeColor
    var secondaryText: ThemeColor
    var caret: ThemeColor
    var fadedText: ThemeColor
    var error: ThemeColor
    var extraInput: ThemeColor
    var colorfulError: ThemeColor
    var colorfulExtraInput: ThemeColor
    var prefersDark: Bool

    init(
        id: UUID = UUID(), name: String, background: ThemeColor, panel: ThemeColor, accent: ThemeColor,
        text: ThemeColor? = nil, secondaryText: ThemeColor? = nil, error: ThemeColor? = nil,
        extraInput: ThemeColor? = nil, caret: ThemeColor? = nil, fadedText: ThemeColor? = nil,
        colorfulError: ThemeColor? = nil, colorfulExtraInput: ThemeColor? = nil, prefersDark: Bool
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.panel = panel
        self.accent = accent
        self.prefersDark = prefersDark
        let colorScheme: ColorScheme = prefersDark ? .dark : .light
        self.text = text ?? .init(color: ResolvedTheme.defaultTextColor(for: colorScheme))
        self.secondaryText = secondaryText ?? .init(
            color: ResolvedTheme.defaultSecondaryTextColor(for: colorScheme))
        self.error = error ?? .init(color: ResolvedTheme.defaultErrorColor)
        self.extraInput = extraInput ?? .init(color: ResolvedTheme.defaultErrorColor)
        self.caret = caret ?? accent
        self.fadedText = fadedText ?? self.secondaryText
        self.colorfulError = colorfulError ?? self.error
        self.colorfulExtraInput = colorfulExtraInput ?? self.extraInput
    }

    var resolvedTheme: ResolvedTheme {
        .init(
            background: background.color, panel: panel.color, accent: accent.color,
            colorScheme: prefersDark ? .dark : .light, text: text.color,
            secondaryText: secondaryText.color, error: error.color, extraInput: extraInput.color,
            caret: caret.color, fadedText: fadedText.color, colorfulError: colorfulError.color,
            colorfulExtraInput: colorfulExtraInput.color)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, background, panel, accent, text, secondaryText, error, extraInput, caret,
            fadedText, colorfulError, colorfulExtraInput, prefersDark
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        background = try values.decode(ThemeColor.self, forKey: .background)
        panel = try values.decode(ThemeColor.self, forKey: .panel)
        accent = try values.decode(ThemeColor.self, forKey: .accent)
        prefersDark = try values.decode(Bool.self, forKey: .prefersDark)
        let colorScheme: ColorScheme = prefersDark ? .dark : .light
        text = try values.decodeIfPresent(ThemeColor.self, forKey: .text)
            ?? .init(color: ResolvedTheme.defaultTextColor(for: colorScheme))
        secondaryText = try values.decodeIfPresent(ThemeColor.self, forKey: .secondaryText)
            ?? .init(color: ResolvedTheme.defaultSecondaryTextColor(for: colorScheme))
        error = try values.decodeIfPresent(ThemeColor.self, forKey: .error)
            ?? .init(color: ResolvedTheme.defaultErrorColor)
        extraInput = try values.decodeIfPresent(ThemeColor.self, forKey: .extraInput)
            ?? .init(color: ResolvedTheme.defaultErrorColor)
        caret = try values.decodeIfPresent(ThemeColor.self, forKey: .caret) ?? accent
        fadedText = try values.decodeIfPresent(ThemeColor.self, forKey: .fadedText) ?? secondaryText
        colorfulError = try values.decodeIfPresent(ThemeColor.self, forKey: .colorfulError) ?? error
        colorfulExtraInput = try values.decodeIfPresent(ThemeColor.self, forKey: .colorfulExtraInput)
            ?? extraInput
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(background, forKey: .background)
        try values.encode(panel, forKey: .panel)
        try values.encode(accent, forKey: .accent)
        try values.encode(text, forKey: .text)
        try values.encode(secondaryText, forKey: .secondaryText)
        try values.encode(error, forKey: .error)
        try values.encode(extraInput, forKey: .extraInput)
        try values.encode(caret, forKey: .caret)
        try values.encode(fadedText, forKey: .fadedText)
        try values.encode(colorfulError, forKey: .colorfulError)
        try values.encode(colorfulExtraInput, forKey: .colorfulExtraInput)
        try values.encode(prefersDark, forKey: .prefersDark)
    }
}

enum AppTheme: String, CaseIterable, Codable, Equatable {
    case paper
    case midnight
    case grove
    case aurora
    case beach
    case diner
    case alpine
    case botanical
    case copper
    case honey
    case iceberg_dark
    case lavender
    case sunset
    case watermelon
    case breeze
    case camping
    case cherry_blossom
    case desert_oasis
    case grape
    case moonlight
    case blueberry_dark
    case blueberry_light
    case cafe
    case cheesecake
    case creamsicle
    case fire
    case iceberg_light
    case mountain
    case mint
    case nebula
    case olive
    case strawberry
    case blue_dolphin
    case earthsong
    case fleuriste
    case froyo
    case fruit_chew
    case hedge
    case lilac_mist
    case lime
    case luna
    case matcha_moccha
    case menthol
    case mizu
    case nautilus
    case peach_blossom
    case peaches
    case tangerine
    case tiramisu
    case terra
    case aether
    case bento
    case hanok
    case carbon
    case horizon
    case laser
    case `80s_after_dark`
    case bliss
    case bouquet
    case comfy
    case dino
    case floret
    case grand_prix
    case hammerhead
    case incognito
    case leather
    case arch
    case bingsu
    case godspeed
    case macroblank
    case pastel
    case bushido
    case drowning
    case evil_eye
    case joker
    case matrix
    case dark
    case dots
    case graen
    case milkshake
    case pink_lemonade
    case soaring_skies
    case taro
    case terrazzo
    case viridescent
    case wavez
    case chaos_theory
    case cyberspace
    case dark_note
    case darling
    case dev
    case dollar
    case dualshot
    case everblush
    case ez_mode
    case fledgling
    case metropolis
    case modern_ink
    case phantom
    case pulse
    case repose_dark
    case repose_light
    case retro
    case shadow
    case terminal
    case vaporwave
    case fundamentals
    case muted
    case passion_fruit
    case purpleish
    case sewing_tin_light
    case future_funk
    case night_runner
    case norse
    case retrocast
    case stealth
    case `8008`
    case `9009`
    case alduin
    case anti_hero
    case frozen_llama
    case husqy
    case ishtar
    case iv_clover
    case iv_spade
    case lil_dragon
    case magic_girl
    case mashu
    case material
    case metaverse
    case mexican
    case miami
    case miami_nights
    case modern_dolch
    case modern_dolch_light
    case mr_sleeves
    case ms_cupcakes
    case oblivion
    case olivia
    case red_dragon
    case red_samurai
    case shoko

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    private struct Palette {
        let background: Color
        let panel: Color
        let accent: Color
        let text: Color?
        let secondaryText: Color?
        let error: Color?
        let colorScheme: ColorScheme
    }

    private static func palette(
        _ background: UInt32, _ panel: UInt32, _ accent: UInt32,
        _ text: UInt32, _ secondaryText: UInt32, light: Bool, error: UInt32? = nil
    ) -> Palette {
        .init(
            background: rgb(background), panel: rgb(panel), accent: rgb(accent),
            text: rgb(text), secondaryText: rgb(secondaryText),
            error: error.map(rgb),
            colorScheme: light ? .light : .dark)
    }

    var displayName: String {
        switch self {
        case .paper: "纸白"
        case .midnight: "午夜"
        case .grove: "林地"
        case .aurora: "极光 · Typebar"
        case .beach: "海岸 · Typebar"
        case .diner: "夜间餐厅 · Typebar"
        case .alpine: "高山 · Typebar"
        case .botanical: "植物园 · Typebar"
        case .copper: "铜绿 · Typebar"
        case .honey: "蜂蜜 · Typebar"
        case .iceberg_dark: "暗海冰 · Typebar"
        case .lavender: "薰衣草 · Typebar"
        case .sunset: "落日 · Typebar"
        case .watermelon: "西瓜 · Typebar"
        case .breeze: "微风 · Typebar"
        case .camping: "露营 · Typebar"
        case .cherry_blossom: "樱花 · Typebar"
        case .desert_oasis: "沙漠绿洲 · Typebar"
        case .grape: "葡萄 · Typebar"
        case .moonlight: "月光 · Typebar"
        case .blueberry_dark: "深蓝莓 · Typebar"
        case .blueberry_light: "浅蓝莓 · Typebar"
        case .cafe: "咖啡馆 · Typebar"
        case .cheesecake: "芝士蛋糕 · Typebar"
        case .creamsicle: "奶油橘 · Typebar"
        case .fire: "火光 · Typebar"
        case .iceberg_light: "浅海冰 · Typebar"
        case .mountain: "山峦 · Typebar"
        case .mint: "薄荷 · Typebar"
        case .nebula: "星云 · Typebar"
        case .olive: "橄榄 · Typebar"
        case .strawberry: "草莓 · Typebar"
        case .blue_dolphin: "海豚蓝 · Typebar"
        case .earthsong: "大地之歌 · Typebar"
        case .fleuriste: "花店 · Typebar"
        case .froyo: "冻酸奶 · Typebar"
        case .fruit_chew: "果糖 · Typebar"
        case .hedge: "绿篱 · Typebar"
        case .lilac_mist: "丁香雾 · Typebar"
        case .lime: "青柠 · Typebar"
        case .luna: "月夜 · Typebar"
        case .matcha_moccha: "抹茶摩卡 · Typebar"
        case .menthol: "薄荷冰 · Typebar"
        case .mizu: "水蓝 · Typebar"
        case .nautilus: "鹦鹉螺 · Typebar"
        case .peach_blossom: "桃花 · Typebar"
        case .peaches: "蜜桃 · Typebar"
        case .tangerine: "橘瓣 · Typebar"
        case .tiramisu: "提拉米苏 · Typebar"
        case .terra: "陶土 · Typebar"
        case .aether: "晴空薄雾 · Typebar"
        case .bento: "漆盒彩格 · Typebar"
        case .hanok: "木格纸窗 · Typebar"
        case .carbon: "石墨 · Typebar"
        case .horizon: "暮色地平线 · Typebar"
        case .laser: "霓虹光束 · Typebar"
        case .`80s_after_dark`: "八十年代夜色 · Typebar"
        case .bliss: "晴霁 · Typebar"
        case .bouquet: "花束 · Typebar"
        case .comfy: "舒适角落 · Typebar"
        case .dino: "蕨绿恐龙 · Typebar"
        case .floret: "夜花 · Typebar"
        case .grand_prix: "赛道 · Typebar"
        case .hammerhead: "锤头鲨 · Typebar"
        case .incognito: "隐身 · Typebar"
        case .leather: "皮革 · Typebar"
        case .arch: "石拱 · Typebar"
        case .bingsu: "冰沙 · Typebar"
        case .godspeed: "疾行 · Typebar"
        case .macroblank: "留白 · Typebar"
        case .pastel: "粉彩 · Typebar"
        case .bushido: "漆夜 · Typebar"
        case .drowning: "深潜 · Typebar"
        case .evil_eye: "邪眼 · Typebar"
        case .joker: "纸牌 · Typebar"
        case .matrix: "矩阵 · Typebar"
        case .dark: "暗铅 · Typebar"
        case .dots: "墨点 · Typebar"
        case .graen: "苔石 · Typebar"
        case .milkshake: "莓奶 · Typebar"
        case .pink_lemonade: "粉柠 · Typebar"
        case .soaring_skies: "高空 · Typebar"
        case .taro: "芋紫 · Typebar"
        case .terrazzo: "水磨石 · Typebar"
        case .viridescent: "铜锈绿 · Typebar"
        case .wavez: "浪纹 · Typebar"
        case .chaos_theory: "混沌图谱 · Typebar"
        case .cyberspace: "数据海 · Typebar"
        case .dark_note: "暗色手记 · Typebar"
        case .darling: "柔玫 · Typebar"
        case .dev: "开发室 · Typebar"
        case .dollar: "纸币绿 · Typebar"
        case .dualshot: "双镜头 · Typebar"
        case .everblush: "长春绯 · Typebar"
        case .ez_mode: "轻松模式 · Typebar"
        case .fledgling: "新羽 · Typebar"
        case .metropolis: "城市钠灯 · Typebar"
        case .modern_ink: "现代蓝墨 · Typebar"
        case .phantom: "薄雾幽影 · Typebar"
        case .pulse: "脉冲 · Typebar"
        case .repose_dark: "深色休憩 · Typebar"
        case .repose_light: "浅色休憩 · Typebar"
        case .retro: "复古磁带 · Typebar"
        case .shadow: "钢影 · Typebar"
        case .terminal: "琥珀终端 · Typebar"
        case .vaporwave: "晚潮 · Typebar"
        case .fundamentals: "制图纸 · Typebar"
        case .muted: "灰绿陶釉 · Typebar"
        case .passion_fruit: "果肉紫心 · Typebar"
        case .purpleish: "紫色颜料 · Typebar"
        case .sewing_tin_light: "浅色搪瓷盒 · Typebar"
        case .future_funk: "舞厅织物 · Typebar"
        case .night_runner: "夜路沥青 · Typebar"
        case .norse: "峡湾石 · Typebar"
        case .retrocast: "老显像管 · Typebar"
        case .stealth: "隐身机壳 · Typebar"
        case .`8008`: "金属仪表 · Typebar"
        case .`9009`: "瓷面仪表 · Typebar"
        case .alduin: "熔岩石层 · Typebar"
        case .anti_hero: "靛蓝织物 · Typebar"
        case .frozen_llama: "冰蓝纱线 · Typebar"
        case .husqy: "灰褐毛毡 · Typebar"
        case .ishtar: "星蚀石 · Typebar"
        case .iv_clover: "四叶草纸 · Typebar"
        case .iv_spade: "黑桃机壳 · Typebar"
        case .lil_dragon: "小龙苔 · Typebar"
        case .magic_girl: "月亮丝绒 · Typebar"
        case .mashu: "莓粉瓷 · Typebar"
        case .material: "矿物蓝灰 · Typebar"
        case .metaverse: "深海数据 · Typebar"
        case .mexican: "玉米纸 · Typebar"
        case .miami: "滨海珊瑚 · Typebar"
        case .miami_nights: "夜航海岸 · Typebar"
        case .modern_dolch: "深灰陶 · Typebar"
        case .modern_dolch_light: "浅灰陶 · Typebar"
        case .mr_sleeves: "针织袖口 · Typebar"
        case .ms_cupcakes: "莓果糖霜 · Typebar"
        case .oblivion: "薄雾钛 · Typebar"
        case .olivia: "橄榄羊皮 · Typebar"
        case .red_dragon: "龙鳞朱 · Typebar"
        case .red_samurai: "朱漆刀鞘 · Typebar"
        case .shoko: "雨后纸窗 · Typebar"
        }
    }

    var background: Color {
        palette.background
    }

    var panel: Color {
        palette.panel
    }

    var accent: Color {
        palette.accent
    }

    var colorScheme: ColorScheme {
        palette.colorScheme
    }

    var resolvedTheme: ResolvedTheme {
        let colors = palette
        return .init(
            background: colors.background, panel: colors.panel, accent: colors.accent,
            colorScheme: colors.colorScheme, text: colors.text,
            secondaryText: colors.secondaryText, error: colors.error, extraInput: colors.error)
    }

    private var palette: Palette {
        switch self {
        case .paper:
            .init(
                background: Color(red: 0.96, green: 0.95, blue: 0.91),
                panel: Color(red: 0.88, green: 0.86, blue: 0.80),
                accent: Color(red: 0.66, green: 0.28, blue: 0.14),
                text: nil, secondaryText: nil, error: nil, colorScheme: .light)
        case .midnight:
            .init(
                background: Color(red: 0.07, green: 0.09, blue: 0.13),
                panel: Color(red: 0.13, green: 0.16, blue: 0.22),
                accent: Color(red: 0.38, green: 0.73, blue: 1.00),
                text: nil, secondaryText: nil, error: nil, colorScheme: .dark)
        case .grove:
            .init(
                background: Color(red: 0.09, green: 0.16, blue: 0.13),
                panel: Color(red: 0.14, green: 0.25, blue: 0.19),
                accent: Color(red: 0.48, green: 0.78, blue: 0.52),
                text: nil, secondaryText: nil, error: nil, colorScheme: .dark)
        case .aurora:
            Self.palette(0x10272C, 0x1E3C41, 0xB8D98B, 0xEDF3E8, 0xB7CFCC, light: false)
        case .beach:
            Self.palette(0xE0F0F3, 0xC7DEE3, 0xA13D38, 0x193D49, 0x48636B, light: true)
        case .diner:
            Self.palette(0x282532, 0x45394A, 0xEABF79, 0xF3E9DC, 0xCDBFCC, light: false)
        case .alpine:
            Self.palette(0xE8F0ED, 0xCFDED8, 0x2F5F73, 0x173B45, 0x3F626B, light: true)
        case .botanical:
            Self.palette(0x1B2D25, 0x294538, 0xD2C59B, 0xF0EEE0, 0xC3D0BD, light: false)
        case .copper:
            Self.palette(0x17373C, 0x2A5154, 0xE2A775, 0xF7EDE2, 0xC8D5D0, light: false)
        case .honey:
            Self.palette(0xEAD68D, 0xDCC47D, 0x5D4128, 0x312D1F, 0x5A4B2C, light: true)
        case .iceberg_dark:
            Self.palette(0x132B3A, 0x23485B, 0xA9D6D8, 0xE9F5F6, 0xB6D0D6, light: false)
        case .lavender:
            Self.palette(0xEEE7F6, 0xDAD0EA, 0x634899, 0x302746, 0x60546F, light: true)
        case .sunset:
            Self.palette(0x382434, 0x573747, 0xFFBF8D, 0xFFF0E6, 0xE1C5C8, light: false)
        case .watermelon:
            Self.palette(0xE9F3E5, 0xCFE2C8, 0xA53655, 0x1E3F36, 0x43675C, light: true)
        case .breeze:
            Self.palette(0xDCECF0, 0xC1DDE3, 0x276877, 0x173842, 0x42616B, light: true)
        case .camping:
            Self.palette(0x2B3025, 0x424A35, 0xE5BA75, 0xF2EBDC, 0xCACDB9, light: false)
        case .cherry_blossom:
            Self.palette(0xF7EAF0, 0xE9D4DF, 0x8E3E64, 0x3F2A3A, 0x664C5D, light: true)
        case .desert_oasis:
            Self.palette(0xEBDABB, 0xDCC79E, 0x2F6671, 0x3B3525, 0x514A3C, light: true)
        case .grape:
            Self.palette(0x302640, 0x493756, 0xDBB7F1, 0xF7ECFA, 0xD4C3DC, light: false)
        case .moonlight:
            Self.palette(0x1D2A3E, 0x2C3E53, 0xE6D6A5, 0xEEF2F4, 0xC4D0D8, light: false)
        case .blueberry_dark:
            Self.palette(0x1A233C, 0x2D3754, 0xBAA5E6, 0xF3EFFA, 0xC3C3D8, light: false)
        case .blueberry_light:
            Self.palette(0xE8EEF8, 0xCFDBEE, 0x4E4F99, 0x1F2C4C, 0x4A5874, light: true)
        case .cafe:
            Self.palette(0x2C251F, 0x49382E, 0xE8BE81, 0xF4ECE0, 0xD6C8B7, light: false)
        case .cheesecake:
            Self.palette(0xF5EBCB, 0xEADCA9, 0x6B4A19, 0x3B3422, 0x5E5139, light: true)
        case .creamsicle:
            Self.palette(0xFFF0DF, 0xF1D7B8, 0xA04724, 0x3F2D27, 0x6C5148, light: true)
        case .fire:
            Self.palette(0x301D1D, 0x4A2A28, 0xFFC078, 0xFCEDE1, 0xDEC4BE, light: false)
        case .iceberg_light:
            Self.palette(0xE6F5F7, 0xCBE6EC, 0x2E6877, 0x153944, 0x466570, light: true)
        case .mountain:
            Self.palette(0x1D2C33, 0x2E454A, 0xB9D7B3, 0xEEF3EC, 0xBED0CC, light: false)
        case .mint:
            Self.palette(0xDDF2EA, 0xC4E3D5, 0x286E5A, 0x173B34, 0x42675B, light: true)
        case .nebula:
            Self.palette(0x211F39, 0x373451, 0xCDB6F1, 0xF3F0FA, 0xC8C2D8, light: false)
        case .olive:
            Self.palette(0x282D20, 0x3D4930, 0xD4CF89, 0xF2F1E4, 0xC9CEB4, light: false)
        case .strawberry:
            Self.palette(0xFBEDEF, 0xF1D5DB, 0x9C3D57, 0x472B35, 0x6B4A55, light: true)
        case .blue_dolphin:
            Self.palette(0xC4E4EC, 0xADD0DA, 0x185A76, 0x133244, 0x345661, light: true, error: 0x942C41)
        case .earthsong:
            Self.palette(0x32312C, 0x4A4E39, 0xD5C197, 0xF3F0DD, 0xCBD1B5, light: false, error: 0xF3A899)
        case .fleuriste:
            Self.palette(0xE6EDDA, 0xCFDDBB, 0x85365C, 0x303E32, 0x445A45, light: true, error: 0x942C41)
        case .froyo:
            Self.palette(0xF7E6EB, 0xEACCD5, 0x476B72, 0x3E2D38, 0x684656, light: true, error: 0x942C41)
        case .fruit_chew:
            Self.palette(0xEFBBC2, 0xDEA0AD, 0x6A284A, 0x3E2932, 0x513443, light: true, error: 0x942C41)
        case .hedge:
            Self.palette(0x22332D, 0x354A3B, 0xD0DAB4, 0xEDF2DF, 0xC3D1BC, light: false, error: 0xF3A899)
        case .lilac_mist:
            Self.palette(0xDEE0F0, 0xC6C9E2, 0x65518F, 0x2C3457, 0x484C70, light: true, error: 0x942C41)
        case .lime:
            Self.palette(0x26321D, 0x455339, 0xD6EE8D, 0xF0F5D9, 0xCDD7AF, light: false, error: 0xF3A899)
        case .luna:
            Self.palette(0x303044, 0x48475E, 0xBDD7EA, 0xF1F0F8, 0xCCD0E1, light: false, error: 0xF3A899)
        case .matcha_moccha:
            Self.palette(0x334132, 0x49583F, 0xE5C188, 0xF1EFDA, 0xD7D9BC, light: false, error: 0xF3A899)
        case .menthol:
            Self.palette(0xD2EEE9, 0xB4DCD1, 0x216B67, 0x173C3A, 0x335C55, light: true, error: 0x942C41)
        case .mizu:
            Self.palette(0x193C50, 0x29566C, 0xEDBE90, 0xEDF5F2, 0xBFD7DD, light: false, error: 0xF3A899)
        case .nautilus:
            Self.palette(0x172C46, 0x27445E, 0xEFD498, 0xEFF2F7, 0xBDC9D7, light: false, error: 0xF3A899)
        case .peach_blossom:
            Self.palette(0xF6DED9, 0xE9C1B8, 0x8D3D54, 0x432D35, 0x673E44, light: true, error: 0x942C41)
        case .peaches:
            Self.palette(0xF1D2AF, 0xDFB88E, 0x6A4D27, 0x3F3225, 0x5C4230, light: true, error: 0x942C41)
        case .tangerine:
            Self.palette(0x552D24, 0x764538, 0xFFD393, 0xFFF0DE, 0xF8D2BD, light: false, error: 0xF3A899)
        case .tiramisu:
            Self.palette(0xE9D6BE, 0xD9C09F, 0x554825, 0x392F29, 0x5D4E3E, light: true, error: 0x942C41)
        case .terra:
            Self.palette(0x3E302C, 0x5B4640, 0xE5B69E, 0xF5EDE1, 0xDACCC1, light: false, error: 0xF3A899)
        case .aether:
            Self.palette(0xECEAF7, 0xD6D4EA, 0x4F4C98, 0x262743, 0x525269, light: true, error: 0x8E314A)
        case .bento:
            Self.palette(0xF4E5D8, 0xE5D0BF, 0x8A3F32, 0x382B2C, 0x604B48, light: true, error: 0x882842)
        case .hanok:
            Self.palette(0xEAE2CE, 0xD5C6A9, 0x335C48, 0x302F27, 0x524C3F, light: true, error: 0x943340)
        case .carbon:
            Self.palette(0x20272B, 0x344148, 0x9AE0D5, 0xF2F5F2, 0xC3D4D1, light: false, error: 0xFF9B9B)
        case .horizon:
            Self.palette(0x202F45, 0x354B62, 0xF5BF8C, 0xF5F1E9, 0xC9D4DD, light: false, error: 0xFF9EAB)
        case .laser:
            Self.palette(0x2F213C, 0x493354, 0xF29AD3, 0xF9EDF7, 0xD9C6D8, light: false, error: 0xFCB08F)
        case .`80s_after_dark`:
            Self.palette(0x29213D, 0x3F3151, 0xF9BDB6, 0xFFF3E8, 0xDCCBDE, light: false, error: 0xFFB3AA)
        case .bliss:
            Self.palette(0xE8F2F7, 0xCEE2EB, 0x315A77, 0x233443, 0x496273, light: true, error: 0x9C3444)
        case .bouquet:
            Self.palette(0xF1E5EC, 0xDCC6D4, 0x7A3C66, 0x382A37, 0x59465A, light: true, error: 0x932E46)
        case .comfy:
            Self.palette(0x342D3B, 0x4B4152, 0xEEC7A1, 0xF7F0E7, 0xDED2DB, light: false, error: 0xFFADA8)
        case .dino:
            Self.palette(0xE4E7C8, 0xCBD2AA, 0x3F5C35, 0x2C3727, 0x485446, light: true, error: 0x903B40)
        case .floret:
            Self.palette(0x203442, 0x33505C, 0xFFC4D5, 0xF3F7F5, 0xCDDEDC, light: false, error: 0xFFB2A2)
        case .grand_prix:
            Self.palette(0x222830, 0x3A424A, 0xF6D780, 0xF5F6F1, 0xCBD2D3, light: false, error: 0xFFAA9A)
        case .hammerhead:
            Self.palette(0xDBEAE7, 0xB7D1D0, 0x275E65, 0x233B40, 0x3F5B60, light: true, error: 0x9A3845)
        case .incognito:
            Self.palette(0x252D40, 0x3B4558, 0xCFC8F3, 0xF7F7FB, 0xCED5E7, light: false, error: 0xFFB9A8)
        case .leather:
            Self.palette(0xEAD9C0, 0xD3BC9F, 0x663C35, 0x332925, 0x544237, light: true, error: 0x8A2F40)
        case .arch:
            Self.palette(0xE1E8ED, 0xC6D2DB, 0x315A6F, 0x20323B, 0x455965, light: true, error: 0x8B354C)
        case .bingsu:
            Self.palette(0xEFE8F3, 0xDCD0E6, 0x63466F, 0x29283D, 0x514E67, light: true, error: 0x8F344B)
        case .godspeed:
            Self.palette(0xE5EDF1, 0xC7D9DF, 0x315D73, 0x1D3540, 0x405F6B, light: true, error: 0x9A3545)
        case .macroblank:
            Self.palette(0xF1F3F2, 0xD9DEDD, 0x315260, 0x252E32, 0x4D5D61, light: true, error: 0x962E49)
        case .pastel:
            Self.palette(0xE9E9F4, 0xD5D7EA, 0x5F518D, 0x2B304B, 0x515674, light: true, error: 0x973D55)
        case .bushido:
            Self.palette(0x292838, 0x403C4D, 0xE2B68C, 0xF5F0EA, 0xCED0DE, light: false, error: 0xF2A8A1)
        case .drowning:
            Self.palette(0x092E3A, 0x174554, 0xA7D8CF, 0xE8F5F0, 0xBED8DD, light: false, error: 0xFBB09A)
        case .evil_eye:
            Self.palette(0x242B55, 0x384578, 0xEDD79B, 0xF5F4EE, 0xCDD7EA, light: false, error: 0xFFB4AB)
        case .joker:
            Self.palette(0x312936, 0x4B3D52, 0xD9D497, 0xF6F1EA, 0xD6C9D8, light: false, error: 0xF4A8AA)
        case .matrix:
            Self.palette(0x162C25, 0x234438, 0xB7D6A2, 0xEDF4E7, 0xC9D9C9, light: false, error: 0xFFAD9E)
        case .dark:
            Self.palette(0x20242B, 0x343A43, 0xD7B978, 0xF3F2EA, 0xC4CCD2, light: false, error: 0xFFAB9D)
        case .dots:
            Self.palette(0xE5E7E2, 0xCCD1CB, 0x315E57, 0x243934, 0x455C55, light: true, error: 0x983B4A)
        case .graen:
            Self.palette(0xDCE7D6, 0xC3D6C3, 0x325F4F, 0x24382D, 0x435948, light: true, error: 0x973A4B)
        case .milkshake:
            Self.palette(0xF1E1E1, 0xE1CCD0, 0x75415D, 0x382B34, 0x654C5B, light: true, error: 0x973F4B)
        case .pink_lemonade:
            Self.palette(0xFBE6D3, 0xEFCDCA, 0x974052, 0x472F36, 0x6E4A54, light: true, error: 0x934043)
        case .soaring_skies:
            Self.palette(0x1D334D, 0x2F4D68, 0xECC994, 0xF0F3F4, 0xC4D4DB, light: false, error: 0xFFB3A5)
        case .taro:
            Self.palette(0xE9E0EB, 0xD4C4D9, 0x604C82, 0x312A3D, 0x584D64, light: true, error: 0x924050)
        case .terrazzo:
            Self.palette(0xE6E1D5, 0xD0C8B7, 0x3F675F, 0x33352F, 0x505749, light: true, error: 0x8E3C47)
        case .viridescent:
            Self.palette(0x102F30, 0x244A49, 0xD2C78F, 0xE8F3EC, 0xC5D6CD, light: false, error: 0xFFB39E)
        case .wavez:
            Self.palette(0x162F48, 0x294A65, 0x99D6D9, 0xEDF3F3, 0xC2D4D9, light: false, error: 0xFFB0A4)
        case .chaos_theory:
            Self.palette(0x242433, 0x373A4B, 0xDCD28B, 0xF5F0E8, 0xCFD0D7, light: false, error: 0xFFB3A1)
        case .cyberspace:
            Self.palette(0x142F3F, 0x244659, 0xA9E6D8, 0xEFF8F4, 0xBED6DD, light: false, error: 0xFFB6A7)
        case .dark_note:
            Self.palette(0x252624, 0x3B403B, 0xE8CD9E, 0xF5F0E5, 0xD0D2C8, light: false, error: 0xFFB0A0)
        case .darling:
            Self.palette(0xF2E8E6, 0xE1D4D4, 0x7A3B58, 0x382933, 0x5B4753, light: true, error: 0x8E3349)
        case .dev:
            Self.palette(0xE4EAEF, 0xCDD9E0, 0x315B75, 0x243746, 0x465F70, light: true, error: 0x983F48)
        case .dollar:
            Self.palette(0xE8EDD8, 0xD3DFC0, 0x3E6246, 0x28382D, 0x485C4A, light: true, error: 0x983C48)
        case .dualshot:
            Self.palette(0x28313B, 0x3C4B56, 0xE9B8AB, 0xF0F4F2, 0xCBD4D7, light: false, error: 0xFFB7A5)
        case .everblush:
            Self.palette(0xEEE5E9, 0xDCCFD8, 0x6D466D, 0x332C3D, 0x594D62, light: true, error: 0x8F3B50)
        case .ez_mode:
            Self.palette(0xF1E9D6, 0xDED3B8, 0x365F67, 0x303A37, 0x4F5A50, light: true, error: 0x943D4C)
        case .fledgling:
            Self.palette(0x22352E, 0x355046, 0xDCCF95, 0xF1F4E9, 0xC9D9CC, light: false, error: 0xFFB6A8)
        case .metropolis:
            Self.palette(0x1C2B32, 0x30424A, 0xF5C277, 0xF7F0E5, 0xCAD4D0, light: false, error: 0xFFAD9B)
        case .modern_ink:
            Self.palette(0xE8EDF0, 0xD0DBE1, 0x315E73, 0x22323C, 0x485F69, light: true, error: 0x9A3547)
        case .phantom:
            Self.palette(0x272334, 0x3D354A, 0xD4C1E9, 0xF5F0F7, 0xD0C8DA, light: false, error: 0xFFAA9A)
        case .pulse:
            Self.palette(0x351F2C, 0x4D3040, 0xF2BC9A, 0xFAF0E9, 0xDFC8D3, light: false, error: 0xFFB2A5)
        case .repose_dark:
            Self.palette(0x243239, 0x394A50, 0xC4D9C6, 0xF0F4EF, 0xC5D4D0, light: false, error: 0xFFB2A1)
        case .repose_light:
            Self.palette(0xE5EBE6, 0xC9D9D3, 0x4B546D, 0x283443, 0x4D5B64, light: true, error: 0x943B50)
        case .retro:
            Self.palette(0xE5D6B5, 0xCDBD9B, 0x3D5A5A, 0x302B24, 0x524B3C, light: true, error: 0x8C3744)
        case .shadow:
            Self.palette(0x1A2832, 0x2C3945, 0xB6D9DA, 0xF2F4F2, 0xC0D2D3, light: false, error: 0xFFA99C)
        case .terminal:
            Self.palette(0x121D26, 0x233444, 0xE4C98E, 0xF3F0E0, 0xC7D2C9, light: false, error: 0xFFB4A1)
        case .vaporwave:
            Self.palette(0x302443, 0x4E365A, 0xABE0C9, 0xF8EFF7, 0xD8CEDF, light: false, error: 0xFFB09E)
        case .fundamentals:
            Self.palette(0xF0F2EE, 0xDDE3DF, 0x315F77, 0x263843, 0x455A62, light: true, error: 0x913A46)
        case .muted:
            Self.palette(0xDCE1D9, 0xC8D0C5, 0x4B5D6A, 0x27382F, 0x4A5B51, light: true, error: 0x8C374D)
        case .passion_fruit:
            Self.palette(0xF3D7BC, 0xE5BFA8, 0x773655, 0x3F2B35, 0x5E3F4C, light: true, error: 0x8E2D3B)
        case .purpleish:
            Self.palette(0xE8E1F0, 0xD1C7DF, 0x59417C, 0x302840, 0x514663, light: true, error: 0x8D3449)
        case .sewing_tin_light:
            Self.palette(0xE4E9E5, 0xC8D1CB, 0x2E6463, 0x27363A, 0x44555A, light: true, error: 0x91384C)
        case .future_funk:
            Self.palette(0x2C2432, 0x47394B, 0xE6B8DA, 0xF4EDF2, 0xD6C5D4, light: false, error: 0xF7A998)
        case .night_runner:
            Self.palette(0x1B2730, 0x2D3B46, 0xEFD08A, 0xF1F3EE, 0xC6D3D0, light: false, error: 0xFFAFA0)
        case .norse:
            Self.palette(0x263A40, 0x39565A, 0xE7C79C, 0xF5F1E7, 0xCCD9D5, light: false, error: 0xFFA7A0)
        case .retrocast:
            Self.palette(0x2D302A, 0x434B3D, 0xDDE7A1, 0xF2F0DF, 0xD1D4BD, light: false, error: 0xF6AD9A)
        case .stealth:
            Self.palette(0x161D25, 0x28323A, 0xA8C9D0, 0xF2F5F4, 0xC5D1D5, light: false, error: 0xFFA9A1)
        case .`8008`:
            Self.palette(0x252C31, 0x3B464A, 0xE8C39D, 0xF4F0E9, 0xC9D0C9, light: false, error: 0xFFA79F)
        case .`9009`:
            Self.palette(0xE6E9E6, 0xCCD5D1, 0x365F68, 0x24363A, 0x485D5F, light: true, error: 0x913947)
        case .alduin:
            Self.palette(0x302D2C, 0x4A423D, 0xE8C296, 0xF5F0E5, 0xD0C9BD, light: false, error: 0xF5A69D)
        case .anti_hero:
            Self.palette(0x262837, 0x3E4353, 0xDDC0BB, 0xF3F0F0, 0xCACCD4, light: false, error: 0xFFAEA3)
        case .frozen_llama:
            Self.palette(0xE4EDF2, 0xCBDDE7, 0x375D78, 0x243641, 0x465A69, light: true, error: 0x913F51)
        case .husqy:
            Self.palette(0xE9E4DD, 0xD1C8BD, 0x5B4B43, 0x302D2B, 0x514C48, light: true, error: 0x913F46)
        case .ishtar:
            Self.palette(0x27243A, 0x3C3654, 0xE8C7A3, 0xF4F0EB, 0xC9C9D4, light: false, error: 0xFFA89B)
        case .iv_clover:
            Self.palette(0xDFEAD9, 0xC8DAC2, 0x375D4A, 0x24392F, 0x45594B, light: true, error: 0x913947)
        case .iv_spade:
            Self.palette(0x1C2A32, 0x30414A, 0xBDD9D4, 0xF1F4EF, 0xC0CED0, light: false, error: 0xFFA89B)
        case .lil_dragon:
            Self.palette(0xE5ECE6, 0xCBDCD0, 0x496354, 0x263830, 0x4E5A53, light: true, error: 0x913947)
        case .magic_girl:
            Self.palette(0x332541, 0x4C3655, 0xF0BFD7, 0xF8EFF6, 0xD8C7D6, light: false, error: 0xFFA89B)
        case .mashu:
            Self.palette(0xF0E4EC, 0xDFCADA, 0x744C6A, 0x392D38, 0x5A4957, light: true, error: 0x913947)
        case .material:
            Self.palette(0xE0E7E8, 0xC8D6D9, 0x315E6C, 0x24363E, 0x465D62, light: true, error: 0x913947)
        case .metaverse:
            Self.palette(0x1D2D43, 0x30445B, 0xADD8D6, 0xF0F4F4, 0xC5D3DB, light: false, error: 0xFFA89B)
        case .mexican:
            Self.palette(0xEDE3C7, 0xDACDAA, 0x6B4D22, 0x3C3325, 0x5C503C, light: true, error: 0x913947)
        case .miami:
            Self.palette(0xD9EEF0, 0xBCDBDE, 0x8C3D66, 0x233842, 0x495D64, light: true, error: 0x913947)
        case .miami_nights:
            Self.palette(0x272C45, 0x3D4260, 0xF3B7C0, 0xF5F0F2, 0xCFCAD9, light: false, error: 0xFFA89B)
        case .modern_dolch:
            Self.palette(0x2E3238, 0x434B50, 0xD6D3AA, 0xF0F2EB, 0xC8D1CB, light: false, error: 0xFFA89B)
        case .modern_dolch_light:
            Self.palette(0xEAEAE3, 0xD4D7CF, 0x4E6361, 0x303B3A, 0x50605D, light: true, error: 0x913947)
        case .mr_sleeves:
            Self.palette(0x302C30, 0x4A3E43, 0xEBC8AA, 0xF4EFEB, 0xD0C9C6, light: false, error: 0xFFA89B)
        case .ms_cupcakes:
            Self.palette(0xF2DFE1, 0xE5C5CB, 0x81455E, 0x3A2C36, 0x654C58, light: true, error: 0x913947)
        case .oblivion:
            Self.palette(0x232838, 0x353E50, 0xC6D0EA, 0xF2F3F8, 0xC8CFDA, light: false, error: 0xFFA89B)
        case .olivia:
            Self.palette(0xE8E3D7, 0xD2CAB8, 0x5D6447, 0x343A2E, 0x4F5541, light: true, error: 0x913947)
        case .red_dragon:
            Self.palette(0x35252A, 0x51373D, 0xF1B7A2, 0xFAF0EB, 0xE1CAC7, light: false, error: 0xFFD591)
        case .red_samurai:
            Self.palette(0x302829, 0x483738, 0xE5C09B, 0xF5F1EA, 0xD4C9C0, light: false, error: 0xF5A79A)
        case .shoko:
            Self.palette(0xE3ECEC, 0xC6DCDD, 0x35647A, 0x283A42, 0x4B6268, light: true, error: 0x913947)
        }
    }
}
