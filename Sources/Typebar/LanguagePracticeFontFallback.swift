import AppKit

/// Adds an installed script font to macOS's fallback cascade for languages
/// whose glyph coverage benefits from it. The primary font always remains
/// the user's selected font; no font data is bundled, downloaded, or changed
/// in the user's settings.
enum LanguagePracticeFontFallback {
  private static func identifiers(for language: TypingLanguage) -> [String] {
    switch language {
    case .lao: ["Noto_Sans_Lao"]
    case .sindhi: ["Noto_Naskh_Arabic"]
    default: []
    }
  }

  static func preferredPostScriptNames(
    for language: TypingLanguage, resolve: (String) -> String?
  ) -> [String] {
    identifiers(for: language).compactMap(resolve)
  }

  static func applying(to primary: NSFont, language: TypingLanguage) -> NSFont {
    let descriptors = preferredPostScriptNames(for: language, resolve: NativePracticeFont.postScriptName)
      .compactMap { NSFont(name: $0, size: primary.pointSize)?.fontDescriptor }
    guard !descriptors.isEmpty else { return primary }
    let descriptor = primary.fontDescriptor.addingAttributes([
      .cascadeList: descriptors
    ])
    return NSFont(descriptor: descriptor, size: primary.pointSize) ?? primary
  }
}
