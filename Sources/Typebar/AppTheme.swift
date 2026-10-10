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

struct ResolvedTheme {
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
        }
    }
}
