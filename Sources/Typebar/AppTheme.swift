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
    let colorScheme: ColorScheme
}

/// Original, code-drawn practice backgrounds. These intentionally avoid image
/// assets so the visual treatment stays local to Typebar and theme-aware.
enum PracticeBackdropStyle: String, CaseIterable, Codable, Equatable, Identifiable {
    case solid
    case halos
    case grid

    var id: Self { self }

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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            GeometryReader { proxy in
                let phase = reduceMotion || systemReduceMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate / 4)
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
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
    var prefersDark: Bool

    init(id: UUID = UUID(), name: String, background: ThemeColor, panel: ThemeColor, accent: ThemeColor, prefersDark: Bool) {
        self.id = id
        self.name = name
        self.background = background
        self.panel = panel
        self.accent = accent
        self.prefersDark = prefersDark
    }

    var resolvedTheme: ResolvedTheme {
        .init(background: background.color, panel: panel.color, accent: accent.color, colorScheme: prefersDark ? .dark : .light)
    }
}

enum AppTheme: String, CaseIterable, Codable, Equatable {
    case paper
    case midnight
    case grove

    var displayName: String {
        switch self {
        case .paper: "纸白"
        case .midnight: "午夜"
        case .grove: "林地"
        }
    }

    var background: Color {
        switch self {
        case .paper: Color(red: 0.96, green: 0.95, blue: 0.91)
        case .midnight: Color(red: 0.07, green: 0.09, blue: 0.13)
        case .grove: Color(red: 0.09, green: 0.16, blue: 0.13)
        }
    }

    var panel: Color {
        switch self {
        case .paper: Color(red: 0.88, green: 0.86, blue: 0.80)
        case .midnight: Color(red: 0.13, green: 0.16, blue: 0.22)
        case .grove: Color(red: 0.14, green: 0.25, blue: 0.19)
        }
    }

    var accent: Color {
        switch self {
        case .paper: Color(red: 0.66, green: 0.28, blue: 0.14)
        case .midnight: Color(red: 0.38, green: 0.73, blue: 1.00)
        case .grove: Color(red: 0.48, green: 0.78, blue: 0.52)
        }
    }

    var colorScheme: ColorScheme {
        self == .paper ? .light : .dark
    }

    var resolvedTheme: ResolvedTheme {
        .init(background: background, panel: panel, accent: accent, colorScheme: colorScheme)
    }
}
