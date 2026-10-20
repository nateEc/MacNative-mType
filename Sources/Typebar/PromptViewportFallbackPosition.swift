import AppKit

/// One-shot, same-target reading anchor across field-page layout transitions
/// and experimental-to-complete fallback. It owns no view or persisted state.
@MainActor final class PromptViewportFallbackPosition: NSObject {
  private weak var source: PromptViewportPracticeNativeView?
  private weak var completeSource: PromptFieldNativeView?
  private var pending: PromptViewportNativeScrollHost.ReadingPosition?
  var hasPendingPosition: Bool { pending != nil }
  private weak var page: NSScrollView?
  private var lastBounds: CGRect = .zero
  private var lastDocumentFrame: CGRect = .zero

  deinit { NotificationCenter.default.removeObserver(self) }

  func register(_ source: PromptViewportPracticeNativeView) {
    self.source = source
    completeSource = nil
  }

  func register(_ source: PromptFieldNativeView) {
    completeSource = source
    self.source = nil
  }

  func captureForFocusChange() {
    guard pending == nil else { return }
    if let completeSource, let position = completeSource.readingPositionForFocusChange(),
      let page = completeSource.enclosingScrollView {
      capture(position, in: page)
    }
  }

  func capture(attemptID: UUID, targetID: UUID) {
    guard let position = source?.readingPositionForFallback(),
      position.attemptID == attemptID, position.promptTargetID == targetID,
      let page = source?.enclosingScrollView else {
      clear()
      return
    }
    capture(position, in: page)
  }

  func capture(_ position: PromptViewportNativeScrollHost.ReadingPosition, in page: NSScrollView) {
    clear()
    guard let document = page.documentView else { return }
    pending = position
    self.page = page
    lastBounds = page.contentView.bounds
    lastDocumentFrame = document.frame
    page.contentView.postsBoundsChangedNotifications = true
    document.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
      name: NSView.boundsDidChangeNotification, object: page.contentView)
    NotificationCenter.default.addObserver(self, selector: #selector(documentChanged),
      name: NSView.frameDidChangeNotification, object: document)
  }

  private func clear() {
    pending = nil
    page = nil
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func documentChanged() {
    guard let page, let document = page.documentView else { clear(); return }
    lastBounds = page.contentView.bounds
    lastDocumentFrame = document.frame
  }

  @objc private func boundsChanged() {
    guard let page, let document = page.documentView else { clear(); return }
    let next = page.contentView.bounds
    if next.origin != lastBounds.origin, next.size == lastBounds.size,
      document.frame == lastDocumentFrame {
      clear()
      return
    }
    lastBounds = next
    lastDocumentFrame = document.frame
  }

  func restore(in view: NSView, attemptID: UUID, targetID: UUID,
    rectForCharacter: (Int) -> CGRect?) {
    guard let position = pending else { return }
    guard position.attemptID == attemptID, position.promptTargetID == targetID else {
      clear()
      return
    }
    guard let page, view.enclosingScrollView === page else { clear(); return }
    guard let document = page.documentView,
      view.bounds.width > 1, view.bounds.height > 1,
      view.convert(view.bounds, to: document).maxY <= document.bounds.maxY + 0.01,
      let rect = rectForCharacter(position.character) else { return }
    let point = view.convert(.init(x: rect.minX,
      y: rect.minY + position.rowFraction * rect.height), to: document)
    var next = page.contentView.bounds
    next.origin.y = point.y
    clear()
    page.contentView.scroll(to: page.contentView.constrainBoundsRect(next).origin)
    page.reflectScrolledClipView(page.contentView)
  }
}
