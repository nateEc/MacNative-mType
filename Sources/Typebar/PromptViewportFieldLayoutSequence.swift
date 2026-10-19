import AppKit

/// Offscreen, sequential field windows from one immutable session snapshot.
/// The visible host must still validate its own request and publish identity;
/// this sequence is not a replacement for full-text accessibility or scrolling.
@MainActor final class PromptViewportFieldLayoutSequence {
  struct Window {
    let fields: Range<Int>
    let runs: [PromptFieldTextRun]
    let layout: PromptFieldTextLayout
  }

  private let session: TypingSession
  private let directory: PromptViewportTargetDirectory
  private let style: PromptRenderStyle
  private let width: CGFloat
  private let font: NSFont
  private let lineSpacing: CGFloat
  private let rightToLeft: Bool
  private let joinsLetters: Bool
  private var checkpoint: PromptFieldTextLayout.ContinuationCheckpoint?
  private(set) var nextField = 0
  var contentHeight: CGFloat? { checkpoint?.contentHeight }

  init?(session: TypingSession, directory: PromptViewportTargetDirectory,
    style: PromptRenderStyle, width: CGFloat, font: NSFont,
    lineSpacing: CGFloat = 12, rightToLeft: Bool = false, joinsLetters: Bool = false) {
    guard width.isFinite, width > 0, directory.fieldCount > 0,
      directory.attemptID == session.automaticInputAttemptID,
      directory.promptTargetID == session.promptTargetID else { return nil }
    self.session = session
    self.directory = directory
    self.style = style
    self.width = width
    self.font = font
    self.lineSpacing = lineSpacing
    self.rightToLeft = rightToLeft
    self.joinsLetters = joinsLetters
  }

  /// A failed or skipped window never advances the flow checkpoint.
  func append(fields: Range<Int>) -> Window? {
    guard !fields.isEmpty, fields.lowerBound == nextField,
      fields.upperBound <= directory.fieldCount,
      let runs = PromptRenderPlan.renderIndependentFieldWindow(
        directory: directory, session: session, fields: fields, style: style)
    else { return nil }
    let layout: PromptFieldTextLayout
    if let checkpoint {
      guard let continued = PromptFieldTextLayout.continuing(fieldRuns: runs,
        from: checkpoint, groupOffset: fields.lowerBound, width: width,
        font: font, lineSpacing: lineSpacing,
        rightToLeft: rightToLeft, joinsLetters: joinsLetters) else { return nil }
      layout = continued
    } else {
      layout = PromptFieldTextLayout(fieldRuns: runs, width: width,
        font: font, lineSpacing: lineSpacing,
        rightToLeft: rightToLeft, joinsLetters: joinsLetters)
    }
    guard let next = layout.continuationCheckpoint,
      next.nextGroupOffset == fields.upperBound else { return nil }
    self.checkpoint = next
    nextField = fields.upperBound
    return .init(fields: fields, runs: runs, layout: layout)
  }
}
