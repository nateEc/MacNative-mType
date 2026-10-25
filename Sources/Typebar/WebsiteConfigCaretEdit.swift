import Foundation

/// These four source setters update presentation or a future repeat preference;
/// none dispatches a restart, changes pace selection, or mutates input rules.
enum WebsiteConfigCaretEdit {
  static let keys: Set<String> = ["smoothCaret", "caretStyle", "paceCaretStyle", "repeatedPace"]
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}

extension CaretCommandTarget {
  var websiteKey: String {
    switch self {
    case .smooth: "smoothCaret"; case .primary: "caretStyle"
    case .pace: "paceCaretStyle"; case .repeatedPace: "repeatedPace"
    }
  }
  var websiteValue: WebsiteConfigValue {
    switch self {
    case .smooth(let value): .string(value.rawValue)
    case .primary(let value), .pace(let value): .string(value.compatibilityValue)
    case .repeatedPace(let value): .bool(value)
    }
  }
  /// The source accepts decorative styles in imported configurations but hides
  /// them in both command subgroups. Retain them for legacy Typebar commands.
  var visibleInWebsiteCommandPalette: Bool {
    switch self {
    case .primary(let value), .pace(let value): ![.carrot, .banana, .monkey].contains(value)
    default: true
    }
  }
}
