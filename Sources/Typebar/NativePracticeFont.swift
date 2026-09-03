import AppKit
import SwiftUI

/// Resolves a user-supplied name against fonts already installed on this Mac.
/// No font data is copied, embedded, or installed by Typebar.
enum NativePracticeFont {
  static let maximumNameLength = 50

  static var fallbackPostScriptName: String {
    NSFont.systemFont(ofSize: 12).fontName
  }

  static func normalizedName(_ name: String) -> String {
    String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
  }

  static func postScriptName(for requestedName: String) -> String? {
    let name = normalizedName(requestedName)
    guard !name.isEmpty else { return nil }

    if NSFont(name: name, size: 1) != nil {
      return name
    }

    guard
      let member = NSFontManager.shared.availableMembers(ofFontFamily: name)?.first,
      let postScriptName = member.first as? String,
      NSFont(name: postScriptName, size: 1) != nil
    else { return nil }
    return postScriptName
  }

  static func font(named requestedName: String, size: Double) -> Font? {
    guard let postScriptName = postScriptName(for: requestedName) else { return nil }
    return .custom(postScriptName, size: size)
  }

  static func nsFont(named requestedName: String, size: CGFloat) -> NSFont? {
    guard let postScriptName = postScriptName(for: requestedName) else { return nil }
    return NSFont(name: postScriptName, size: size)
  }

  static func isAvailable(_ requestedName: String) -> Bool {
    postScriptName(for: requestedName) != nil
  }
}
