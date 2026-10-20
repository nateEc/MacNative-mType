import AppKit
import SwiftUI

struct PromptViewportPresentationReady: Equatable {
  let attemptID: UUID
  let targetID: UUID
  let style: PromptRenderStyle
  let font: NSFont
  let width: CGFloat
  let height: CGFloat
}

/// Reference identity avoids SwiftUI comparing the full session's value tree.
@MainActor fileprivate final class PromptViewportPracticeSnapshot {
  let session: TypingSession
  let style: PromptRenderStyle
  let font: NSFont
  let carets: PromptCaretNativeView.Configuration
  let lineSpacing: CGFloat
  let rightToLeft: Bool
  let joinsLetters: Bool
  init(session: TypingSession, style: PromptRenderStyle, font: NSFont,
    carets: PromptCaretNativeView.Configuration) {
    self.session = session; self.style = style; self.font = font; self.carets = carets
    lineSpacing = session.configuration.usesJoiningScriptPrompt ? 8 : 12
    rightToLeft = session.configuration.usesRightToLeftPrompt
    joinsLetters = session.configuration.usesJoiningScriptPrompt
  }
}

struct PromptViewportPracticePrompt: View {
  private let snapshot: PromptViewportPracticeSnapshot
  let onFailure: (UUID) -> Void
  let onReady: (PromptViewportPresentationReady) -> Void
  let wrapLayout: PromptInputWrapLayout?
  let fallbackPosition: PromptViewportFallbackPosition?
  @State private var height: CGFloat = 1
  init(session: TypingSession, style: PromptRenderStyle, font: NSFont,
    carets: PromptCaretNativeView.Configuration, wrapLayout: PromptInputWrapLayout? = nil,
    fallbackPosition: PromptViewportFallbackPosition? = nil,
    onFailure: @escaping (UUID) -> Void,
    onReady: @escaping (PromptViewportPresentationReady) -> Void = { _ in }) {
    snapshot = .init(session: session, style: style, font: font, carets: carets)
    self.onFailure = onFailure
    self.onReady = onReady
    self.wrapLayout = wrapLayout
    self.fallbackPosition = fallbackPosition
  }
  var body: some View {
    PromptViewportPracticeBridge(snapshot: snapshot, onFailure: onFailure, onReady: onReady, wrapLayout: wrapLayout,
      fallbackPosition: fallbackPosition,
      onHeight: { height = $0 }).frame(height: height)
  }
}

private struct PromptViewportPracticeBridge: NSViewRepresentable {
  let snapshot: PromptViewportPracticeSnapshot
  let onFailure: (UUID) -> Void
  let onReady: (PromptViewportPresentationReady) -> Void
  let wrapLayout: PromptInputWrapLayout?
  let fallbackPosition: PromptViewportFallbackPosition?
  let onHeight: (CGFloat) -> Void
  func makeNSView(context: Context) -> PromptViewportPracticeNativeView { .init() }
  func updateNSView(_ view: PromptViewportPracticeNativeView, context: Context) {
    view.configure(snapshot, onFailure: onFailure, onHeight: onHeight, onReady: onReady)
    wrapLayout?.view = view.viewport.canvas
    fallbackPosition?.source = view
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptViewportPracticeNativeView,
    context: Context) -> CGSize? {
    .init(width: max(1, proposal.width ?? nsView.bounds.width), height: proposal.height ?? nsView.measuredHeight)
  }
  static func dismantleNSView(_ view: PromptViewportPracticeNativeView, coordinator: ()) { view.stop() }
}

/// Owns only the presentation bridge. The existing practice page still owns
/// input, scoring and the complete rendering fallback.
@MainActor final class PromptViewportPracticeNativeView: NSView {
  let viewport = PromptViewportNativeScrollHost(pageScrolling: true)
  private(set) var measuredHeight: CGFloat = 1
  private var snapshot: PromptViewportPracticeSnapshot?
  private var applied: PromptViewportPracticeSnapshot?
  private var appliedWidth: CGFloat = 0
  private var directory: PromptViewportTargetDirectory?
  private var onFailure: ((UUID) -> Void)?
  private var onHeight: ((CGFloat) -> Void)?
  private var onReady: ((PromptViewportPresentationReady) -> Void)?
  private var reportedReady: PromptViewportPresentationReady?
  private var reportedFailure: PromptViewportPracticeSnapshot?
  private var pendingReadingPosition: PromptViewportNativeScrollHost.ReadingPosition?
  private var readingPositionWasSuperseded = false
  private let batchSize = 32

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    addSubview(viewport)
    viewport.onPreparationFailure = { [weak self] _ in self?.reportFailure() }
    viewport.onLayoutWidthChange = { [weak self] in self?.needsLayout = true }
    viewport.onLayoutWillRetire = { [weak self] in self?.rememberReadingPosition() }
    viewport.onMeasuredHeightChange = { [weak self] in self?.publishHeight($0) }
    viewport.onExternalNavigation = { [weak self] in
      guard let self, self.pendingReadingPosition != nil else { return }
      self.readingPositionWasSuperseded = true
    }
  }
  required init?(coder: NSCoder) { fatalError("PromptViewportPracticeNativeView is created in code") }

  fileprivate func configure(_ snapshot: PromptViewportPracticeSnapshot, onFailure: @escaping (UUID) -> Void,
    onHeight: @escaping (CGFloat) -> Void,
    onReady: @escaping (PromptViewportPresentationReady) -> Void) {
    self.snapshot = snapshot; self.onFailure = onFailure; self.onHeight = onHeight
    self.onReady = onReady
    needsLayout = true
    reconcile()
  }
  override func setFrameSize(_ newSize: NSSize) {
    if abs(newSize.width - bounds.width) >= 0.001 { rememberReadingPosition() }
    super.setFrameSize(newSize)
    needsLayout = true
  }
  override func layout() {
    super.layout()
    reconcile()
    viewport.refreshPageVisibility()
    restoreReadingPositionIfReady()
    reportReadyIfNeeded()
  }
  private func reconcile() {
    guard let snapshot, bounds.width.isFinite, bounds.width > 1 else { return }
    if viewport.frame != bounds { viewport.frame = bounds }
    let width = viewport.layoutWidth
    guard width.isFinite, width > 1 else { return }
    guard applied !== snapshot || appliedWidth != width || viewport.measuredFieldCount == 0 else { return }
    let sameTarget = applied?.session.automaticInputAttemptID == snapshot.session.automaticInputAttemptID
      && applied?.session.promptTargetID == snapshot.session.promptTargetID
    let sameMetrics = appliedWidth == width && applied?.font == snapshot.font
      && applied?.lineSpacing == snapshot.lineSpacing && applied?.rightToLeft == snapshot.rightToLeft
      && applied?.joinsLetters == snapshot.joinsLetters
    if sameTarget && sameMetrics && viewport.measuredFieldCount > 0 {
      guard viewport.replaceVisibleSession(snapshot.session, style: snapshot.style) else { reportFailure(); return }
    } else {
      if sameTarget { rememberReadingPosition() }
      else { pendingReadingPosition = nil; readingPositionWasSuperseded = false }
      if directory?.attemptID != snapshot.session.automaticInputAttemptID
        || directory?.promptTargetID != snapshot.session.promptTargetID {
        directory = PromptViewportTargetDirectory(session: snapshot.session)
      }
      guard let directory,
        let sequence = PromptViewportFieldLayoutSequence(session: snapshot.session, directory: directory,
          style: snapshot.style, width: width, font: snapshot.font, lineSpacing: snapshot.lineSpacing,
          rightToLeft: snapshot.rightToLeft, joinsLetters: snapshot.joinsLetters),
        sequence.append(fields: 0..<min(batchSize, sequence.fieldCount)) != nil,
        viewport.configure(sequence: sequence, batchSize: batchSize) else { reportFailure(); return }
    }
    viewport.configureCaret(snapshot.carets)
    applied = snapshot; appliedWidth = width
    reportedFailure = nil
  }
  private func publishHeight(_ height: CGFloat) {
    guard let snapshot else { return }
    if measuredHeight == height { needsLayout = true; return }
    measuredHeight = height
    invalidateIntrinsicContentSize()
    DispatchQueue.main.async { [weak self] in
      guard let self, self.snapshot?.session.automaticInputAttemptID == snapshot.session.automaticInputAttemptID,
        self.snapshot?.session.promptTargetID == snapshot.session.promptTargetID,
        self.measuredHeight == height else { return }
      self.onHeight?(height)
      self.needsLayout = true
    }
  }
  private func restoreReadingPositionIfReady() {
    guard let position = pendingReadingPosition, viewport.canvas.hasCompleteHeight,
      abs(bounds.height - measuredHeight) < 0.01 else { return }
    pendingReadingPosition = nil
    if readingPositionWasSuperseded {
      readingPositionWasSuperseded = false
      if viewport.canvas.accessibilitySelectedTextRange().location == NSNotFound {
        viewport.canvas.restoreAccessibilitySelection(position.selection)
      }
      return
    }
    guard viewport.restoreReadingPosition(position) else { reportFailure(); return }
  }
  private func rememberReadingPosition() {
    if pendingReadingPosition == nil { pendingReadingPosition = viewport.captureReadingPosition() }
  }
  func readingPositionForFallback() -> PromptViewportNativeScrollHost.ReadingPosition? {
    if !readingPositionWasSuperseded, let pendingReadingPosition { return pendingReadingPosition }
    return viewport.captureReadingPosition()
  }
  private func currentReadiness() -> PromptViewportPresentationReady? {
    guard let snapshot, applied === snapshot, viewport.canvas.hasCompleteHeight,
      abs(bounds.height - measuredHeight) < 0.01,
      abs(appliedWidth - viewport.layoutWidth) < 0.001,
      let document = enclosingScrollView?.documentView,
      document.frame.height >= bounds.height,
      convert(bounds, to: document).maxY <= document.bounds.maxY + 0.01 else { return nil }
    return .init(attemptID: snapshot.session.automaticInputAttemptID,
      targetID: snapshot.session.promptTargetID, style: snapshot.style, font: snapshot.font,
      width: viewport.layoutWidth, height: measuredHeight)
  }
  private func reportReadyIfNeeded() {
    guard let ready = currentReadiness(), reportedReady != ready else { return }
    reportedReady = ready
    DispatchQueue.main.async { [weak self] in
      guard let self, self.reportedReady == ready else { return }
      guard self.currentReadiness() == ready else {
        self.reportedReady = nil
        self.needsLayout = true
        return
      }
      self.onReady?(ready)
    }
  }
  private func reportFailure() {
    guard let snapshot, reportedFailure !== snapshot else { return }
    reportedFailure = snapshot
    DispatchQueue.main.async { [weak self] in
      guard let self, self.snapshot === snapshot else { return }
      self.onFailure?(snapshot.session.automaticInputAttemptID)
    }
  }
  func stop() {
    snapshot = nil; applied = nil; directory = nil
    onFailure = nil; onHeight = nil; reportedFailure = nil; appliedWidth = 0
    onReady = nil; reportedReady = nil
    pendingReadingPosition = nil
    readingPositionWasSuperseded = false
    viewport.stop()
  }
}
