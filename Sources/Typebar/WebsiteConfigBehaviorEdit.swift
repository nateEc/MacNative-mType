import Foundation

enum WebsiteConfigBehaviorEdit {
  /// These setters have no overrides or restart dispatch. Require precisely
  /// one matching event and no unrelated runtime change before bypassing the
  /// restart-only No Quit gate.
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, BehaviorCommandTarget.websiteKeys.contains(edit.key),
      draft.projection.rejectedKeys.isEmpty, draft.projection.events.count == 1,
      draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}

extension BehaviorCommandTarget {
  static let websiteKeys: Set<String> = ["quickRestart", "blindMode", "alwaysShowWordsHistory", "singleListCommandLine"]
  var websiteKey: String {
    switch self {
    case .quickRestart: "quickRestart"
    case .blindMode: "blindMode"
    case .alwaysShowWordsHistory: "alwaysShowWordsHistory"
    case .commandPaletteListMode: "singleListCommandLine"
    }
  }
  var websiteValue: WebsiteConfigValue {
    switch self {
    case .quickRestart(let key): .string(key == .escape ? "esc" : key.rawValue)
    case .blindMode(let enabled), .alwaysShowWordsHistory(let enabled): .bool(enabled)
    case .commandPaletteListMode(let mode): .string(mode == .singleList ? "on" : "manual")
    }
  }
}
