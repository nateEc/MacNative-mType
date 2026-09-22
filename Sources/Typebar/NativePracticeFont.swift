import AppKit
import SwiftUI

/// Resolves a user-supplied name against fonts already installed on this Mac.
/// No font data is copied, embedded, or installed by Typebar.
enum NativePracticeFont {
  static let maximumNameLength = 50
  private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

  static var fallbackPostScriptName: String {
    NSFont.systemFont(ofSize: 12).fontName
  }

  static func normalizedName(_ name: String) -> String {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.rangeOfCharacter(from: .controlCharacters) == nil else { return "" }
    return String(normalized.prefix(maximumNameLength))
  }

  static func postScriptName(for requestedName: String) -> String? {
    postScriptName(for: requestedName, installedFamilies: NSFontManager.shared.availableFontFamilies)
  }

  static func isAvailable(_ requestedName: String, installedFamilies: [String]) -> Bool {
    postScriptName(for: requestedName, installedFamilies: installedFamilies) != nil
  }

  static func postScriptName(for requestedName: String, installedFamilies: [String]) -> String? {
    let name = normalizedName(requestedName)
    guard !name.isEmpty else { return nil }

    for candidate in nameCandidates(for: name) {
      if NSFont(name: candidate, size: 1) != nil {
        return candidate
      }
    }

    guard let family = matchingFamily(for: name, in: installedFamilies) else { return nil }
    return postScriptName(forFamily: family)
  }

  static func font(named requestedName: String, size: Double) -> Font? {
    guard let postScriptName = preferredPostScriptName(for: requestedName) else { return nil }
    return .custom(postScriptName, size: size)
  }

  static func nsFont(named requestedName: String, size: CGFloat) -> NSFont? {
    guard let postScriptName = preferredPostScriptName(for: requestedName) else { return nil }
    return NSFont(name: postScriptName, size: size)
  }

  static func isAvailable(_ requestedName: String) -> Bool {
    postScriptName(for: requestedName) != nil
  }

  static func matchingFamily(for requestedName: String, in installedFamilies: [String]) -> String? {
    let name = normalizedName(requestedName)
    guard !name.isEmpty else { return nil }
    let identity = normalizedIdentity(name)
    return installedFamilies.first { normalizedIdentity($0) == identity }
  }

  private static func nameCandidates(for name: String) -> [String] {
    let spaced = name.replacingOccurrences(of: "_", with: " ")
    return spaced == name ? [name] : [name, spaced]
  }

  private static func normalizedIdentity(_ value: String) -> String {
    String(value.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: comparisonLocale)
      .lowercased(with: comparisonLocale)
  }

  private static func postScriptName(forFamily family: String) -> String? {
    guard
      let member = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first,
      let postScriptName = member.first as? String,
      NSFont(name: postScriptName, size: 1) != nil
    else { return nil }
    return postScriptName
  }

  private static func preferredPostScriptName(for requestedName: String) -> String? {
    TypebarLocalPracticeFontStore.activeInfo?.postScriptName ?? postScriptName(for: requestedName)
  }
}
