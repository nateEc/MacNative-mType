import Foundation

enum WebsiteConfigNativeKeyboardTypographyError: Error, Equatable {
  case missingField(String), invalidField(String), unrepresentableField(String), invalidFontScale
}

/// Model draft only. Input emulation, guide display and font admission are
/// separate; this adapter never registers fonts or changes the current input.
struct WebsiteConfigNativeKeyboardTypography {
  static let mappedKeys: Set<String> = ["layout", "keymapMode", "keymapStyle", "keymapLegendStyle",
    "keymapKeys", "keymapSize", "keymapLayout", "fontFamily", "fontSize", "maxLineWidth"]

  private static let schema = WebsiteConfigSchema(catalogs: .init(languages: [], themes: [],
    layouts: Set(KeyboardLayout.allCases.compactMap(OfficialLayoutCommandCatalog.name)),
    fonts: Set(FontFamilyCommandCatalog.fixedKnownFontIDs), funboxes: []))

  let inputLayout: KeyboardInputLayout
  let guideMode: KeyboardGuideMode
  let guideStyle: KeyboardGuideStyle
  let guideLegendStyle: KeyboardGuideLegendStyle
  let guideKeys: KeyboardGuideKeysMode
  let guideScale: Double
  let guideLayout: KeyboardLayout?
  let fontFamily: String
  let fontSize: Double
  /// Source ch count, including fractions; nil is fluid. Not legacy UI columns.
  let columns: Double?

  func inputMapping(mirrored: Bool) -> KeyboardInputMapping {
    if mirrored, let layout = inputLayout.emulatedLayout { return .mirrored(layout) }
    return inputLayout.inputMapping(for: nil)
  }
  func shiftKeymap(mirrored: Bool) -> KeyboardInputMapping {
    guard let guideLayout else { return .system }
    return mirrored ? .mirrored(guideLayout) : .builtIn(guideLayout)
  }

  /// The caller supplies the native rem base explicitly. The source computes
  /// rem against its root font, not a hard-coded browser/device assumption.
  init(runtime: [String: WebsiteConfigValue], pointsPerRem: Double) throws {
    guard pointsPerRem.isFinite, pointsPerRem > 0 else { throw WebsiteConfigNativeKeyboardTypographyError.invalidFontScale }
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let result = runtime[key] else { throw WebsiteConfigNativeKeyboardTypographyError.missingField(key) }
      return result
    }
    func text(_ key: String) throws -> String {
      guard case .string(let result) = try value(key), result.utf8.allSatisfy({ $0 < 128 })
      else { throw WebsiteConfigNativeKeyboardTypographyError.invalidField(key) }
      return result
    }
    func option<T: RawRepresentable>(_ key: String, _ type: T.Type) throws -> T where T.RawValue == String {
      guard let result = try T(rawValue: text(key)) else { throw WebsiteConfigNativeKeyboardTypographyError.invalidField(key) }
      return result
    }
    func number(_ key: String) throws -> Double {
      let input = try value(key)
      guard case .number(let result) = input, Self.schema.accepts(input, for: key)
      else { throw WebsiteConfigNativeKeyboardTypographyError.invalidField(key) }
      return result
    }
    let layoutName = try text("layout")
    guard Self.schema.accepts(.string(layoutName), for: "layout"),
      let layout = OfficialLayoutCommandCatalog.target(for: "input.layout.\(layoutName)") else {
      throw WebsiteConfigNativeKeyboardTypographyError.invalidField("layout")
    }
    switch layout {
    case .system: inputLayout = .system
    case .builtIn(let selected):
      let native = KeyboardInputLayout(emulating: selected)
      guard native.emulatedLayout == selected else { throw WebsiteConfigNativeKeyboardTypographyError.unrepresentableField("layout") }
      inputLayout = native
    }
    guideMode = try option("keymapMode", KeyboardGuideMode.self)
    guideStyle = try option("keymapStyle", KeyboardGuideStyle.self)
    guideLegendStyle = try option("keymapLegendStyle", KeyboardGuideLegendStyle.self)
    guideKeys = try option("keymapKeys", KeyboardGuideKeysMode.self)
    guideScale = try number("keymapSize")
    guard KeyboardGuideScalePolicy.normalized(guideScale) == guideScale else {
      throw WebsiteConfigNativeKeyboardTypographyError.unrepresentableField("keymapSize")
    }
    let guideName = try text("keymapLayout")
    guard Self.schema.accepts(.string(guideName), for: "keymapLayout"),
      let guide = KeyboardGuideLayoutCommandCatalog.target(for: "keyboard.keymapLayout.\(guideName)") else {
      throw WebsiteConfigNativeKeyboardTypographyError.invalidField("keymapLayout")
    }
    switch guide {
    case .inputSync: guideLayout = nil
    case .builtIn(let selected): guideLayout = selected
    }
    let family = try value("fontFamily")
    guard case .string(let name) = family, Self.schema.accepts(family, for: "fontFamily") else {
      throw WebsiteConfigNativeKeyboardTypographyError.invalidField("fontFamily")
    }
    guard InputTextIdentity.matches(NativePracticeFont.normalizedName(name), name) else {
      throw WebsiteConfigNativeKeyboardTypographyError.unrepresentableField("fontFamily")
    }
    fontFamily = name
    let points = try number("fontSize") * pointsPerRem
    guard points.isFinite, points > 0, PracticeFontSizePolicy.normalized(points) == points else {
      throw WebsiteConfigNativeKeyboardTypographyError.unrepresentableField("fontSize")
    }
    fontSize = points
    let width = try number("maxLineWidth")
    if width == 0 { columns = nil }
    else { columns = width }
  }

  func applying(to snapshot: AppSettingsSnapshot) throws -> AppSettingsSnapshot {
    if let columns {
      guard columns.rounded(.towardZero) == columns,
        Double(PracticeLineWidth.customColumnRange.lowerBound)...Double(PracticeLineWidth.customColumnRange.upperBound) ~= columns
      else { throw WebsiteConfigNativeKeyboardTypographyError.unrepresentableField("maxLineWidth") }
    }
    var result = snapshot
    result.keyboardInputLayout = inputLayout
    result.keyboardGuideMode = guideMode
    result.showKeyboardGuide = guideMode != .off
    result.keyboardGuideStyle = guideStyle
    result.keyboardGuideLegendStyle = guideLegendStyle
    result.keyboardGuideKeysMode = guideKeys
    result.keyboardGuideScale = guideScale
    if let guideLayout {
      result.keyboardLayout = guideLayout
      result.keyboardGuideLayoutSource = .builtIn
    } else { result.keyboardGuideLayoutSource = .websiteEmulation }
    result.installedPracticeFontName = fontFamily
    result.fontSize = fontSize
    if let columns {
      result.practiceLineWidth = .custom
      result.customPracticeLineColumns = Int(columns)
    } else { result.practiceLineWidth = .fluid }
    return result
  }
}
