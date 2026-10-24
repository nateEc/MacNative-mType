import AppKit
import CoreText

enum WebsiteConfigFontResourceError: Error, Equatable { case invalidLimit }

/// Owned font faces and ordered fallback intent, not a global registration,
/// settings mutation or proof of browser/native shaping equivalence.
@MainActor
struct WebsiteConfigFontResource {
  enum Local { case absent, data(Data) }
  enum Candidate: Equatable { case local, family(String), monospace }
  enum LocalFailure: Equatable { case undecodable, resourceLimit }
  struct Face {
    let candidate: Candidate
    let font: NSFont
  }
  let candidates: [Candidate]
  let faces: [Face]
  let ownedLocalData: Data?
  let localFailure: LocalFailure?
  /// Prepared before publication; layout never has to resolve these by name.
  let renderingFont: NSFont
  /// Horizontal CSS ch basis, measured with the owned face and its cascade.
  let chAdvance: Double
  var primary: Face { faces[0] }

  static func compose(primary: NSFont, fallback: [NSFont]) -> NSFont {
    guard !fallback.isEmpty else { return primary }
    let descriptors = fallback.map { CTFontCopyFontDescriptor($0 as CTFont) }
    let attributes = CTFontDescriptorCreateWithAttributes([
      kCTFontCascadeListAttribute: descriptors
    ] as CFDictionary)
    // Copy the face, preserving size/matrix/variation and data identity. A new
    // font matched by primary.fontName would lose same-name private faces.
    return CTFontCreateCopyWithAttributes(primary as CTFont, 0, nil, attributes) as NSFont
  }

  static func candidates(family: String, language: TypingLanguage, hasLocal: Bool) -> [Candidate] {
    [hasLocal ? .local : .family(family)]
      + LanguagePracticeFontFallback.preferredIdentifiers(for: language).map(Candidate.family)
      + [.family("Roboto_Mono"), .family("Vazirharf"), .monospace]
  }
  static func prepare(typography: WebsiteConfigNativeKeyboardTypography, language: TypingLanguage,
    local: Local, maximumBytes: Int = 32 * 1024 * 1024) throws -> Self {
    guard maximumBytes > 0 else { throw WebsiteConfigFontResourceError.invalidLimit }
    var owned: Data?, localFont: NSFont?, failure: LocalFailure?
    let hasLocal: Bool
    switch local {
    case .absent: hasLocal = false
    case .data(let data):
      hasLocal = true
      if data.count > maximumBytes { failure = .resourceLimit }
      else {
        let copy = data.withUnsafeBytes { Data($0) }
        if let descriptors = CTFontManagerCreateFontDescriptorsFromData(copy as CFData) as? [CTFontDescriptor],
          let descriptor = descriptors.first,
          let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
          let font = CTFontCreateWithFontDescriptorAndOptions(descriptor, typography.fontSize, nil, lookupOptions)
          if CTFontCopyPostScriptName(font) as String == name, CTFontGetGlyphCount(font) > 0 {
            owned = copy
            localFont = font as NSFont
          } else { failure = .undecodable }
        } else { failure = .undecodable }
      }
    }
    let candidates = candidates(family: typography.fontFamily, language: language, hasLocal: hasLocal)
    let faces: [Face] = candidates.compactMap { candidate in
      let font: NSFont?
      switch candidate {
      case .local: font = localFont
      case .family(let identifier): font = installed(identifier, size: typography.fontSize)
      case .monospace: font = .monospacedSystemFont(ofSize: typography.fontSize, weight: .regular)
      }
      return font.map { Face(candidate: candidate, font: $0) }
    }
    // The final native monospace candidate is always materialized. Keep the
    // direct face descriptors; prepare the cascade before value publication.
    let renderingFont = compose(primary: faces[0].font, fallback: faces.dropFirst().map(\.font))
    let zero = NSAttributedString(string: "0", attributes: [.font: renderingFont])
    let advance = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(zero as CFAttributedString), nil, nil, nil)
    return .init(candidates: candidates, faces: faces, ownedLocalData: owned, localFailure: failure,
      renderingFont: renderingFont, chAdvance: advance.isFinite && advance > 0 ? advance : renderingFont.pointSize * 0.5)
  }

  private static let lookupOptions: CTFontOptions = [.preventAutoActivation, .preventAutoDownload]
  private static func installed(_ identifier: String, size: Double) -> NSFont? {
    let name = identifier.replacingOccurrences(of: "_", with: " ")
    guard !name.hasPrefix(".") else { return nil } // Private UI fonts require AppKit APIs.
    let font = CTFontCreateWithNameAndOptions(name as CFString, size, nil, lookupOptions)
    let actual = [CTFontCopyPostScriptName(font), CTFontCopyFamilyName(font), CTFontCopyFullName(font)]
    guard actual.contains(where: { ($0 as String).caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
    return font as NSFont
  }
}
