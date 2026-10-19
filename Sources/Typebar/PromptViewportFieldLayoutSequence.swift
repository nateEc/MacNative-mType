import AppKit

/// Offscreen, sequential field windows from one immutable session snapshot.
/// The visible host must still validate its own request and publish identity;
/// this sequence is not a replacement for full-text accessibility or scrolling.
@MainActor final class PromptViewportFieldLayoutSequence {
  struct Window {
    fileprivate let ownerID: UUID
    let fields: Range<Int>
    let runs: [PromptFieldTextRun]
    let layout: PromptFieldTextLayout
  }

  struct DrawingSnapshot {
    let attemptID: UUID
    let promptTargetID: UUID
    let windows: [Window]
    let width: CGFloat
    let measuredHeight: CGFloat
    let hasCompleteHeight: Bool
    let accessibilityText: String
  }

  struct MeasuredSpan {
    let fields: Range<Int>
    let inkY: Range<CGFloat>?
  }

  struct TextLine {
    let y: CGFloat
    var range: NSRange
  }

  private let ownerID = UUID()
  private let session: TypingSession
  private let directory: PromptViewportTargetDirectory
  private let style: PromptRenderStyle
  private let width: CGFloat
  private let font: NSFont
  private let lineSpacing: CGFloat
  private let rightToLeft: Bool
  private let joinsLetters: Bool
  private var checkpoint: PromptFieldTextLayout.ContinuationCheckpoint?
  private var checkpointsByField: [Int: PromptFieldTextLayout.ContinuationCheckpoint] = [:]
  private(set) var measuredSpans: [MeasuredSpan] = []
  private(set) var measuredTextLines: [TextLine] = []
  private(set) var nextField = 0
  var fieldCount: Int { directory.fieldCount }
  var targetUTF16Count: Int { directory.targetUTF16.count }
  func fieldIndex(containingUTF16 offset: Int) -> Int? { directory.fieldIndex(containingUTF16: offset) }
  var layoutWidth: CGFloat { width }
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

  func replacingSession(_ next: TypingSession, style nextStyle: PromptRenderStyle) -> PromptViewportFieldLayoutSequence? {
    guard next.automaticInputAttemptID == directory.attemptID,
      next.promptTargetID == directory.promptTargetID,
      nextStyle.fontSize == style.fontSize else { return nil }
    return .init(session: next, directory: directory, style: nextStyle,
      width: width, font: font, lineSpacing: lineSpacing,
      rightToLeft: rightToLeft, joinsLetters: joinsLetters)
  }

  /// A failed or skipped window never advances the flow checkpoint.
  func append(fields: Range<Int>) -> Window? {
    guard !fields.isEmpty, fields.lowerBound == nextField,
      fields.upperBound <= directory.fieldCount,
      let window = makeWindow(fields: fields, from: checkpoint),
      let next = window.layout.continuationCheckpoint,
      next.nextGroupOffset == fields.upperBound else { return nil }
    if let checkpoint { checkpointsByField[fields.lowerBound] = checkpoint }
    self.checkpoint = next
    nextField = fields.upperBound
    let frames = Array(window.layout.cellFrames.values)
    let lowerY = frames.map(\.minY).min()
    let upperY = frames.map(\.maxY).max()
    measuredSpans.append(.init(fields: fields, inkY: lowerY.flatMap { lower in
      upperY.map { upper in lower..<max(upper, window.layout.size.height) }
    }))
    for (id, rect) in window.layout.cellFrames.sorted(by: { $0.key < $1.key }) {
      if let last = measuredTextLines.last, abs(last.y - rect.minY) < 0.5 {
        measuredTextLines[measuredTextLines.count - 1].range.length = id + 1 - last.range.location
      } else {
        measuredTextLines.append(.init(y: rect.minY, range: .init(location: id, length: 1)))
      }
    }
    return window
  }

  /// Original UTF-16 positions are canonical IDs in this admitted ASCII
  /// directory. Revisit only intersecting measured windows, without scrolling.
  func measuredTextFrame(for range: NSRange) -> CGRect? {
    guard range.location >= 0, range.location <= targetUTF16Count,
      range.length >= 0, range.length <= targetUTF16Count - range.location,
      targetUTF16Count > 0 else { return nil }
    let offset = min(range.location, targetUTF16Count - 1)
    let effective = range.length == 0 ? offset..<(offset + 1) : range.location..<NSMaxRange(range)
    guard let first = fieldIndex(containingUTF16: effective.lowerBound),
      let last = fieldIndex(containingUTF16: effective.upperBound - 1), last < nextField else { return nil }
    var rect = CGRect.null, found = 0
    for span in measuredSpans where span.fields.upperBound > first && span.fields.lowerBound <= last {
      guard let window = revisit(fields: span.fields) else { return nil }
      for (id, frame) in window.layout.cellFrames where effective.contains(id) {
        rect = rect.union(frame); found += 1
      }
    }
    guard found == effective.count else { return nil }
    if range.length == 0 {
      let after = range.location == targetUTF16Count
      if after, directory.targetUTF16.last == 10, let checkpoint {
        let point = checkpoint.flow.continuationOrigin
        return .init(x: rightToLeft ? width - point.x : point.x,
          y: point.y, width: 0, height: rect.height)
      }
      let x = (after != rightToLeft) ? rect.maxX : rect.minX
      return .init(x: x, y: rect.minY, width: 0, height: rect.height)
    }
    return rect
  }

  /// Rebuild an evicted window from its exact saved flow boundary. This never
  /// advances the measured prefix or changes its authoritative page height.
  func revisit(fields: Range<Int>) -> Window? {
    guard !fields.isEmpty, fields.lowerBound >= 0,
      fields.upperBound <= nextField,
      fields.lowerBound == 0 || checkpointsByField[fields.lowerBound] != nil else { return nil }
    return makeWindow(fields: fields,
      from: fields.lowerBound == 0 ? nil : checkpointsByField[fields.lowerBound])
  }

  func measuredTop(forField index: Int) -> CGFloat? {
    guard let span = measuredSpans.first(where: { $0.fields.contains(index) }),
      let window = revisit(fields: span.fields) else { return nil }
    let cells = window.runs.first(where: { $0.fieldID == index })?.cells ?? []
    return cells.compactMap { window.layout.cellFrames[$0.id]?.minY }.min()
      ?? span.inkY?.lowerBound
  }

  private func makeWindow(fields: Range<Int>,
    from start: PromptFieldTextLayout.ContinuationCheckpoint?) -> Window? {
    guard let runs = PromptRenderPlan.renderIndependentFieldWindow(
      directory: directory, session: session, fields: fields, style: style) else { return nil }
    let layout: PromptFieldTextLayout
    let anchor = session.promptCaretGlyphIndex.map {
      PromptCompositionProjection.Anchor(cellID: $0, after: false)
    }
    if let start {
      guard let continued = PromptFieldTextLayout.continuing(fieldRuns: runs,
        from: start, groupOffset: fields.lowerBound, width: width,
        font: font, lineSpacing: lineSpacing,
        rightToLeft: rightToLeft, joinsLetters: joinsLetters,
        anchor: anchor) else { return nil }
      layout = continued
    } else {
      layout = PromptFieldTextLayout(fieldRuns: runs, anchor: anchor, width: width,
        font: font, lineSpacing: lineSpacing,
        rightToLeft: rightToLeft, joinsLetters: joinsLetters)
    }
    return .init(ownerID: ownerID, fields: fields, runs: runs, layout: layout)
  }

  /// Retain only drawable windows chosen by the caller. The height is exact
  /// through nextField, and becomes the full page height only at fieldCount.
  func drawingSnapshot(windows requested: [Window]) -> DrawingSnapshot? {
    guard let checkpoint, !requested.isEmpty,
      requested.allSatisfy({ $0.ownerID == ownerID && $0.fields.upperBound <= nextField
        && $0.layout.matchesMetrics(width: width, font: font, lineSpacing: lineSpacing,
          rightToLeft: rightToLeft, joinsLetters: joinsLetters) }),
      zip(requested, requested.dropFirst()).allSatisfy({ $0.fields.upperBound <= $1.fields.lowerBound })
    else { return nil }
    return .init(attemptID: directory.attemptID, promptTargetID: directory.promptTargetID,
      windows: requested, width: width,
      measuredHeight: checkpoint.contentHeight,
      hasCompleteHeight: nextField == directory.fieldCount,
      accessibilityText: session.prompt)
  }
}
