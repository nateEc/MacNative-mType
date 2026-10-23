import Foundation

enum WebsiteConfigNativeThemesError: Error, Equatable {
  case missingField(String), invalidField(String), invalidNativeThemeName
}

/// Website theme intent only; no library record, account lookup or preference
/// write is implied. Built-in names refer to Typebar's independently drawn styles.
struct WebsiteConfigNativeThemes {
  enum Selection: Equatable { case builtIn(AppTheme), inlineCustom }
  static let mappedKeys: Set<String> = ["theme", "themeLight", "themeDark", "autoSwitchTheme",
    "customTheme", "customThemeColors", "favThemes", "randomTheme"]
  let theme: AppTheme
  let lightTheme: AppTheme
  let darkTheme: AppTheme
  let followsSystem: Bool
  let customEnabled: Bool
  let favorites: [AppTheme]
  let randomMode: RandomThemeMode
  /// Keep spelling as well as RGB: source equality distinguishes #fff/#FFFFFF.
  let customColorHex: [String]
  let customColors: [ThemeColor]

  private static let schema = WebsiteConfigSchema(catalogs: .init(languages: [],
    themes: Set(AppTheme.allCases.filter { $0 != .grove }.map(\.rawValue)),
    layouts: [], fonts: [], funboxes: []))

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativeThemesError.missingField(key) }
      guard Self.schema.accepts(value, for: key) else { throw WebsiteConfigNativeThemesError.invalidField(key) }
      return value
    }
    func name(_ key: String) throws -> String {
      guard case .string(let name) = try value(key) else { throw WebsiteConfigNativeThemesError.invalidField(key) }
      return name
    }
    func flag(_ key: String) throws -> Bool {
      guard case .bool(let flag) = try value(key) else { throw WebsiteConfigNativeThemesError.invalidField(key) }
      return flag
    }
    func strings(_ key: String) throws -> [String] {
      guard case .array(let items) = try value(key) else { throw WebsiteConfigNativeThemesError.invalidField(key) }
      return try items.map {
        guard case .string(let text) = $0 else { throw WebsiteConfigNativeThemesError.invalidField(key) }
        return text
      }
    }
    func themeValue(_ name: String, key: String) throws -> AppTheme {
      guard let theme = AppTheme(rawValue: name), theme != .grove else {
        throw WebsiteConfigNativeThemesError.invalidField(key)
      }
      return theme
    }
    theme = try themeValue(name("theme"), key: "theme")
    lightTheme = try themeValue(name("themeLight"), key: "themeLight")
    darkTheme = try themeValue(name("themeDark"), key: "themeDark")
    followsSystem = try flag("autoSwitchTheme")
    customEnabled = try flag("customTheme")
    favorites = try strings("favThemes").map { try themeValue($0, key: "favThemes") }
    guard let mode = try RandomThemeMode(rawValue: name("randomTheme")) else {
      throw WebsiteConfigNativeThemesError.invalidField("randomTheme")
    }
    randomMode = mode
    customColorHex = try strings("customThemeColors")
    customColors = customColorHex.map { hex in
      let digits = Array(hex.dropFirst())
      let expanded = digits.count == 3 ? digits.flatMap { [$0, $0] } : digits
      // The schema has already admitted exactly 3 or 6 ASCII hex digits.
      let rgb = UInt32(String(expanded), radix: 16)!
      return ThemeColor(red: Double((rgb >> 16) & 255) / 255,
        green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
  }

  func initialSelection(systemIsDark: Bool) -> Selection {
    if followsSystem { return .builtIn(systemIsDark ? darkTheme : lightTheme) }
    return customEnabled ? .inlineCustom : .builtIn(theme)
  }

  func systemAppearanceChange(systemIsDark: Bool) -> Selection? {
    guard followsSystem, !customEnabled else { return nil }
    return .builtIn(systemIsDark ? darkTheme : lightTheme)
  }

  /// Explicit, caller-owned preview only. Does not save or activate a theme.
  func makeCustomTheme(id: UUID, name: String) throws -> CustomThemeDefinition {
    guard name == name.trimmingCharacters(in: .whitespacesAndNewlines),
      (1...40).contains(name.count) else { throw WebsiteConfigNativeThemesError.invalidNativeThemeName }
    let colors = customColors
    let channels = [colors[0].red, colors[0].green, colors[0].blue].map { Int(($0 * 255).rounded()) }
    // Website darkness uses HSL lightness, not relative luminance. For 8-bit
    // RGB, the source's rounded 50% boundary is exactly maxByte + minByte < 255.
    let prefersDark = (channels.max()! + channels.min()!) < 255
    return CustomThemeDefinition(id: id, name: name, background: colors[0], panel: colors[4],
      accent: colors[1], text: colors[5], secondaryText: colors[3], error: colors[6],
      extraInput: colors[7], caret: colors[2], fadedText: colors[4],
      colorfulError: colors[8], colorfulExtraInput: colors[9], prefersDark: prefersDark)
  }
}
