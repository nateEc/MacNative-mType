import Foundation

/// UI sizes use points; the window converts them using its actual rem base.
enum PracticeFontEdit: Equatable {
  case family(String), size(Double)
}

enum WebsiteConfigFontEdit {
  static let keys: Set<String> = ["fontFamily", "fontSize"]
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key),
      draft.projection.rejectedKeys.isEmpty, draft.projection.events.count == 1,
      draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}
