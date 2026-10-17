import AppKit

/// A weak bridge from the text-input responder to the currently presented
/// practice prompt. It owns neither the view nor a presentation timer.
@MainActor final class PromptInsertionAnchor {
  private final class Entry {
    weak var view: PromptCaretNativeView?
    let attemptID: UUID
    init(view: PromptCaretNativeView, attemptID: UUID) {
      self.view = view; self.attemptID = attemptID
    }
  }
  private final class BelowEntry {
    weak var view: BelowCompositionField?
    let attemptID: UUID
    init(view: BelowCompositionField, attemptID: UUID) {
      self.view = view; self.attemptID = attemptID
    }
  }
  private var entries: [Entry] = []
  private var belowEntries: [BelowEntry] = []

  func registerBelow(_ view: BelowCompositionField, attemptID: UUID) {
    belowEntries.removeAll { $0.view == nil || $0.view === view }
    belowEntries.append(BelowEntry(view: view, attemptID: attemptID))
  }

  func unregisterBelow(_ view: BelowCompositionField) {
    belowEntries.removeAll { $0.view == nil || $0.view === view }
  }

  func register(_ view: PromptCaretNativeView, attemptID: UUID) {
    entries.removeAll { $0.view == nil || $0.view === view }
    entries.append(Entry(view: view, attemptID: attemptID))
  }

  func unregister(_ view: PromptCaretNativeView) {
    entries.removeAll { $0.view == nil || $0.view === view }
  }

  func screenRect(attemptID: UUID, in window: NSWindow) -> NSRect? {
    entries.removeAll { $0.view == nil }
    for entry in entries.reversed() {
      guard entry.attemptID == attemptID, let view = entry.view,
        view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
      if let rect = view.insertionScreenRect() { return rect }
    }
    return nil
  }

  func belowInsertionScreenRect(attemptID: UUID, in window: NSWindow,
    location: Int, markedText: String) -> NSRect? {
    belowEntries.removeAll { $0.view == nil }
    for entry in belowEntries.reversed() {
      guard entry.attemptID == attemptID, let view = entry.view,
        view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
      if let rect = view.insertionScreenRect(at: location, markedText: markedText) { return rect }
    }
    return nil
  }

  func markedScreenRect(attemptID: UUID, in window: NSWindow,
    range: NSRange, markedText: String, style: CompositionDisplayStyle) -> (rect: NSRect, actualRange: NSRange)? {
    belowEntries.removeAll { $0.view == nil }
    if style == .below {
      for entry in belowEntries.reversed() {
        guard entry.attemptID == attemptID, let view = entry.view,
          view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
        if let result = view.markedScreenRect(for: range, markedText: markedText) { return result }
      }
    }
    entries.removeAll { $0.view == nil }
    for entry in entries.reversed() {
      guard entry.attemptID == attemptID, let view = entry.view,
        view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
      if let result = view.markedScreenRect(for: range, markedText: markedText, style: style) { return result }
    }
    return nil
  }
}
