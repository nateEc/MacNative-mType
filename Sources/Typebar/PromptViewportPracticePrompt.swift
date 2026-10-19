import AppKit
import SwiftUI

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

struct PromptViewportPracticePrompt: NSViewRepresentable {
  private let snapshot: PromptViewportPracticeSnapshot
  let onFailure: (UUID) -> Void
  init(session: TypingSession, style: PromptRenderStyle, font: NSFont,
    carets: PromptCaretNativeView.Configuration, onFailure: @escaping (UUID) -> Void) {
    snapshot = .init(session: session, style: style, font: font, carets: carets)
    self.onFailure = onFailure
  }
  func makeNSView(context: Context) -> PromptViewportPracticeNativeView { .init() }
  func updateNSView(_ view: PromptViewportPracticeNativeView, context: Context) {
    view.configure(snapshot, onFailure: onFailure)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptViewportPracticeNativeView,
    context: Context) -> CGSize? {
    .init(width: max(1, proposal.width ?? nsView.bounds.width), height: 184)
  }
  static func dismantleNSView(_ view: PromptViewportPracticeNativeView, coordinator: ()) { view.stop() }
}

/// Owns only the presentation bridge. The existing practice page still owns
/// input, scoring and the complete rendering fallback.
@MainActor final class PromptViewportPracticeNativeView: NSView {
  let viewport = PromptViewportNativeScrollHost(frame: .zero)
  private var snapshot: PromptViewportPracticeSnapshot?
  private var applied: PromptViewportPracticeSnapshot?
  private var appliedWidth: CGFloat = 0
  private var directory: PromptViewportTargetDirectory?
  private var onFailure: ((UUID) -> Void)?
  private var reportedFailure: PromptViewportPracticeSnapshot?
  private let batchSize = 32

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    addSubview(viewport)
    viewport.onPreparationFailure = { [weak self] _ in self?.reportFailure() }
    viewport.onLayoutWidthChange = { [weak self] in self?.needsLayout = true }
  }
  required init?(coder: NSCoder) { fatalError("PromptViewportPracticeNativeView is created in code") }

  fileprivate func configure(_ snapshot: PromptViewportPracticeSnapshot, onFailure: @escaping (UUID) -> Void) {
    self.snapshot = snapshot; self.onFailure = onFailure
    needsLayout = true
    reconcile()
  }
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }
  override func layout() {
    super.layout()
    reconcile()
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
    onFailure = nil; reportedFailure = nil; appliedWidth = 0
    viewport.stop()
  }
}
