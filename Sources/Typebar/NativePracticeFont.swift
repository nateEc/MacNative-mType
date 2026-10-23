import AppKit
import SwiftUI

/// Resolves a user-supplied name against fonts already installed on this Mac.
/// No font data is copied, embedded, or installed by Typebar.
enum NativePracticeFont {
  static let maximumNameLength = 50
  private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

  struct Resolver {
    enum Purpose { case practice, catalogPreview }

    let localFont: (CGFloat) -> NSFont?
    let installedFontName: (String) -> String?

    init(
      localFont: @escaping (CGFloat) -> NSFont? = TypebarLocalPracticeFontStore.activeFont(size:),
      installedFontName: @escaping (String) -> String? = {
        NativePracticeFont.postScriptName(for: $0)
      }
    ) {
      self.localFont = localFont
      self.installedFontName = installedFontName
    }

    func font(for requestedName: String, size: CGFloat, purpose: Purpose = .practice) -> NSFont? {
      // Previewing another family must neither substitute nor register the
      // user's active local font; actual practice keeps that explicit override.
      return NativePracticeFont.nsFont(named: requestedName, size: size,
        localFont: purpose == .practice ? localFont : { _ in nil }, installedFontName: installedFontName)
    }
  }

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

  static func postScriptName(for requestedName: String,
    installedFamilies: @autoclosure () -> [String]) -> String? {
    let name = normalizedName(requestedName)
    guard !name.isEmpty else { return nil }

    for candidate in nameCandidates(for: name) {
      if NSFont(name: candidate, size: 1) != nil {
        return candidate
      }
    }

    // The default path commonly has no installed name. Enumerating the system
    // catalog is only needed after validation and direct-name lookup fail.
    guard let family = matchingFamily(for: name, in: installedFamilies()) else { return nil }
    return postScriptName(forFamily: family)
  }

  static func font(named requestedName: String, size: Double) -> Font? {
    if let local = TypebarLocalPracticeFontStore.activeFont(size: size) { return Font(local) }
    guard let postScriptName = postScriptName(for: requestedName) else { return nil }
    return .custom(postScriptName, size: size)
  }

  static func nsFont(named requestedName: String, size: CGFloat,
    localFont: (CGFloat) -> NSFont? = TypebarLocalPracticeFontStore.activeFont(size:),
    installedFontName: (String) -> String? = { postScriptName(for: $0) }) -> NSFont? {
    if let local = localFont(size) { return local }
    // A failed file-bound local lookup must not retry that local font by name.
    guard let postScriptName = installedFontName(requestedName) else { return nil }
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
    // Resolve the canonical family through AppKit before consulting its member
    // list: catalog order is not a default-face contract (e.g. Braille outlines).
    if let font = NSFont(name: family, size: 1) { return font.fontName }
    guard
      let member = NSFontManager.shared.availableMembers(ofFontFamily: family)?.first,
      let postScriptName = member.first as? String,
      NSFont(name: postScriptName, size: 1) != nil
    else { return nil }
    return postScriptName
  }
}

/// Checks availability of the requested challenge family, not the current
/// render cascade. It never installs or bundles Wingdings or accepts a variant.
enum WingdingsChallengeFont {
  static let familyName = "Wingdings"

  static func resolve(size: CGFloat) -> NSFont? {
    guard let name = NativePracticeFont.postScriptName(for: familyName),
      let font = NSFont(name: name, size: size), font.familyName == familyName
    else { return nil }
    return font
  }
}
