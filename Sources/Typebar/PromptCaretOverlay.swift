import AppKit
import SwiftUI

/// Matches the reference speed choices while leaving all interpolation native.
enum SmoothCaretMotion: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case slow
  case medium
  case fast

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .slow: "慢速"
    case .medium: "中速"
    case .fast: "快速"
    }
  }

  var duration: TimeInterval? {
    switch self {
    case .off: nil
    case .slow: 0.15
    case .medium: 0.10
    case .fast: 0.085
    }
  }
}

extension TypingCaretStyle {
  var usesFullGlyphWidth: Bool {
    switch self {
    case .underline, .outline, .block: true
    case .off, .bar, .carrot, .banana, .monkey: false
    }
  }
}

struct PromptRendering {
  let text: AttributedString
  let glyphCharacterOffsets: [Int: Int]
  var emptyWordPlaceholderGlyphID: Int? = nil
  var structuralNewlineOffsets: [Int: Int] = [:]
  var compositionTextMap: PromptCompositionTextMap? = nil

  var mainCharacterOffset: Int? {
    guard let map = compositionTextMap, let anchor = map.caret, let range = map.cellRanges[anchor.cellID] else { return nil }
    return map.characterOffset(atUTF16: range.location)
  }

  static func make(
    glyphs: [TypingPromptGlyph], indices: [Int], emptyWordPlaceholderGlyphID: Int? = nil,
    words: [TypingPromptWordPresentation] = [], removedTapeWordIndices: Set<Int> = [],
    renderGlyph: (Int, TypingPromptGlyph) -> AttributedString
  ) -> Self {
    var text = AttributedString()
    var offsets: [Int: Int] = [:]
    var owners: [Int: Int] = [:], structural: [Int: Int] = [:]
    if !removedTapeWordIndices.isEmpty {
      for (word, value) in words.enumerated() {
        for index in value.range { owners[index] = word }
        for index in value.extraGlyphIndices { owners[index] = word }
      }
      for (word, value) in words.enumerated() {
        let index = value.range.upperBound
        if owners[index] == nil, glyphs.indices.contains(index), glyphs[index].state != .extra,
          glyphs[index].character == " " || glyphs[index].character == "\n" { owners[index] = word }
      }
    }
    for index in indices {
      if let word = owners[index], removedTapeWordIndices.contains(word) {
        // The word's Return ink disappears, but its structural row survives.
        // It deliberately owns no canonical glyph offset or rendering call.
        if glyphs[index].character == "\n", glyphs[index].state != .extra {
          structural[word] = text.characters.count
          text += AttributedString("\n")
        }
        continue
      }
      offsets[index] = text.characters.count
      text += renderGlyph(index, glyphs[index])
    }
    return Self(text: text, glyphCharacterOffsets: offsets,
      emptyWordPlaceholderGlyphID: emptyWordPlaceholderGlyphID.flatMap { offsets[$0] == nil ? nil : $0 },
      structuralNewlineOffsets: structural)
  }

  func characterOffset(forGlyphAt index: Int?) -> Int? {
    guard let index else { return nil }
    return glyphCharacterOffsets[index]
  }

  /// Anonymous structural rows are boundaries, not part of a neighboring
  /// glyph's ink. Build indices once for all attributed-cell consumers.
  func glyphTexts() -> [Int: AttributedString] {
    let indices = Array(text.characters.indices) + [text.endIndex]
    let starts = Set(glyphCharacterOffsets.values).union(structuralNewlineOffsets.values).sorted()
    var texts: [Int: AttributedString] = [:]
    for (index, start) in starts.enumerated() {
      let end = index + 1 < starts.count ? starts[index + 1] : indices.count - 1
      guard start >= 0, end >= start, end < indices.count else { continue }
      texts[start] = AttributedString(text[indices[start]..<indices[end]])
    }
    return texts
  }
}

struct PromptGlyphTextPlan: Equatable {
  let text: String
  let hint: String?
  let opacity: Double
}

/// Native symbols replace control-character icons, not accepted input.
/// Only a source newline owns a line break; a mistyped/extra newline is a
/// visible error in its existing field. Hints remain text, not icons.
enum PromptControlCharacterPresentation {
  static func text(for character: Character, state: TypingPromptCharacterState) -> String {
    plan(for: .init(character: character, state: state), style: .off).text
  }

  static func plan(
    for glyph: TypingPromptGlyph, style: TypoIndicatorStyle,
    isZen: Bool = false, isExtra: Bool = false, compositionReplacement: String? = nil,
    isEmptyWordPlaceholder: Bool = false
  ) -> PromptGlyphTextPlan {
    let extra = isExtra || glyph.state == .extra
    if let compositionReplacement {
      let body = compositionReplacement.map { character -> String in
        if character == " ", !isZen { return "_" }
        if character == "\t" || character == "\n" || character == "\r" { return " " }
        return String(character)
      }.joined()
      return .init(text: body + (!isZen && !extra && glyph.character == "\n" ? "\n" : ""),
        hint: nil, opacity: 1)
    }
    let isControl = glyph.character == "\t" || glyph.character == "\n"
    if isZen {
      if isEmptyWordPlaceholder, glyph.state == .current, glyph.character == " " {
        return .init(text: "_", hint: nil, opacity: 0)
      }
      return .init(text: String(glyph.character), hint: nil, opacity: isControl ? 0 : 1)
    }
    let replaces = glyph.typedCharacter != nil && style.replacesTarget
    let displayed = replaces ? glyph.typedCharacter ?? glyph.character : glyph.character
    let body: String
    if replaces || extra { body = enteredText(for: displayed) }
    else if glyph.character == "\t" { body = "→" }
    else if glyph.character == "\n" { body = "↵" }
    else { body = String(glyph.character) }
    // The original target field owns its line layout even when its Return
    // icon is replaced with a wrong letter. Input errors must not own it.
    let text = body + (!extra && glyph.character == "\n" ? "\n" : "")
    var hint: String?
    if !extra, glyph.state == .incorrect, style.showsHint, let entered = glyph.typedCharacter {
      let character = replaces ? glyph.character : entered
      // HTML hints use ordinary collapsed whitespace, not control icons.
      hint = character == "\t" || character == "\n" || character == "\r"
        ? " " : String(character)
    }
    return .init(text: text, hint: hint, opacity: isControl && !extra ? 0.2 : 1)
  }

  private static func enteredText(for character: Character) -> String {
    switch character {
    case " ": "_"
    case "\t": "→"
    case "\n": "↵"
    default: String(character)
    }
  }
}

struct PromptPaceCaretInterpolation {
  let fromCharacterOffset: Int?
  let targetCharacterOffset: Int?
  let fromAfter: Bool
  let targetAfter: Bool
  let fraction: Double
  var stepDuration: TimeInterval = 0
  var sequence: Double = 0
  var targetGlyphID: Int? = nil
  var zeroDeadlinePredecessor: PaceCaretGlyphAnchor? = nil
  var fromGlyphID: Int? = nil
}

enum PromptPaceCaretGeometry {
  static func rect(from: CGRect, to: CGRect, fromAfter: Bool, toAfter: Bool,
    style: TypingCaretStyle, rightToLeft: Bool, fraction: Double, reducesMotion: Bool,
    afterWidth: CGFloat = 8) -> CGRect {
    func endpoint(_ rect: CGRect, after: Bool) -> CGRect {
      guard after else { return rect }
      if style.usesFullGlyphWidth {
        return CGRect(x: rightToLeft ? rect.minX - afterWidth : rect.maxX,
          y: rect.minY, width: afterWidth, height: rect.height)
      }
      return rect.offsetBy(dx: rightToLeft ? -rect.width : rect.width, dy: 0)
    }
    let start = endpoint(from, after: fromAfter), end = endpoint(to, after: toAfter)
    let t = CGFloat(reducesMotion ? 1 : min(1, max(0, fraction.isFinite ? fraction : 1)))
    return CGRect(x: start.minX + (end.minX - start.minX) * t,
      y: start.minY + (end.minY - start.minY) * t,
      width: start.width + (end.width - start.width) * t,
      height: start.height + (end.height - start.height) * t)
  }
}

/// The reference caret enters an RTL target glyph from its trailing visual
/// edge. Full-width markers still center on the glyph in either direction.
enum PromptCaretPlacementPolicy {
  static func horizontalAnchor(
    for rect: CGRect, style: TypingCaretStyle, isRightToLeft: Bool
  ) -> CGFloat {
    if style.usesFullGlyphWidth { return rect.midX }
    return isRightToLeft ? rect.maxX : rect.minX
  }
}

/// Follows the active glyph inside the native vertical prompt scroller. It
/// observes the same TextKit geometry as the independent caret, but does not
/// replace SwiftUI's attributed text or prevent manual scrolling between keys.
struct PromptAutoScrollOverlay: NSViewRepresentable {
  let text: AttributedString
  let characterOffset: Int?
  let font: NSFont
  let lineSpacing: CGFloat
  let isRightToLeft: Bool
  var lineScroll: PromptLineScrollContext? = nil
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var lineScrollFrameRate

  func makeNSView(context: Context) -> PromptAutoScrollView {
    PromptAutoScrollView()
  }

  func updateNSView(_ nsView: PromptAutoScrollView, context: Context) {
    let lineScroll = lineScroll.map {
      PromptLineScrollContext(attemptID: $0.attemptID, activeWordID: $0.activeWordID,
        characterOffsets: $0.characterOffsets, smoothScroll: $0.smoothScroll,
        reducesMotion: $0.reducesMotion || systemReduceMotion, frameRate: lineScrollFrameRate,
        words: $0.words, firstRetainedWordIndex: $0.firstRetainedWordIndex, onRetire: $0.onRetire,
        followsWordReflow: $0.followsWordReflow, caretMotion: $0.caretMotion,
        centersActiveLine: $0.centersActiveLine, wrapperRevision: $0.wrapperRevision)
    }
    nsView.update(
      text: text, characterOffset: characterOffset, font: font,
      lineSpacing: lineSpacing, isRightToLeft: isRightToLeft, lineScroll: lineScroll)
  }

  static func dismantleNSView(_ nsView: PromptAutoScrollView, coordinator: ()) {
    nsView.cancelCaretMotion()
    nsView.stopLineScroll()
  }
}

final class PromptAutoScrollView: NSView {
  private var text = AttributedString()
  private var characterOffset: Int?
  private var font = NSFont.systemFont(ofSize: 16)
  private var lineSpacing: CGFloat = 12
  private var isRightToLeft = false
  private var lastWidth: CGFloat = 0
  private var isFollowScheduled = false
  private var lineScroll: PromptLineScrollContext?
  private var customGeometry: PromptLineScrollCustomGeometry?
  private var previousWordID: Int?
  private var previousTargetTop: CGFloat = 0
  private var recentersLine = true
  private var resetsAttempt = false
  private var resetsRetainedPrefix = false
  private var lineScrollTimer: Timer?
  private var animatedTarget: CGPoint?
  private var lineScrollAnimation: (from: CGPoint, target: CGPoint, started: TimeInterval)?
  private weak var animatedScrollView: NSScrollView?
  private var lineJumpCount = 0
  private var lineScrollOverlap = PromptLineScrollOverlap()
  private var wordReflow = PromptWordReflowState()
  private var latestActiveTop: CGFloat?
  private var hasPendingWordUpdate = false
  private var pendingRetirement: (value: PromptWordRetirement, notify: (PromptWordRetirement) -> Void)?

  override var isFlipped: Bool { true }

  func update(
    text: AttributedString, characterOffset: Int?, font: NSFont,
    lineSpacing: CGFloat, isRightToLeft: Bool, lineScroll: PromptLineScrollContext? = nil,
    customGeometry: PromptLineScrollCustomGeometry? = nil
  ) {
    let attemptChanged = self.lineScroll?.attemptID != lineScroll?.attemptID
    let prefixChanged = self.lineScroll?.firstRetainedWordIndex != lineScroll?.firstRetainedWordIndex
    let wrapperChanged = self.lineScroll?.wrapperRevision != lineScroll?.wrapperRevision
    let structuralLayoutChanged = self.lineSpacing != lineSpacing
      || self.isRightToLeft != isRightToLeft
      || (self.customGeometry == nil) != (customGeometry == nil)
    let layoutChanged = self.font != font || structuralLayoutChanged
    let textChanged = self.text != text
    let needsFollow = self.characterOffset != characterOffset
      || textChanged
      || self.font != font || self.lineSpacing != lineSpacing
      || self.isRightToLeft != isRightToLeft
      || attemptChanged || prefixChanged || self.lineScroll?.activeWordID != lineScroll?.activeWordID
      || self.lineScroll?.smoothScroll != lineScroll?.smoothScroll
      || self.lineScroll?.reducesMotion != lineScroll?.reducesMotion
      || self.lineScroll?.frameRate != lineScroll?.frameRate
      || self.lineScroll?.followsWordReflow != lineScroll?.followsWordReflow
      || self.lineScroll?.centersActiveLine != lineScroll?.centersActiveLine
      || wrapperChanged
      || self.customGeometry?.revision != customGeometry?.revision
      || self.customGeometry?.caretGlyphID != customGeometry?.caretGlyphID
    if attemptChanged {
      stopLineScroll()
      previousWordID = nil
      previousTargetTop = 0
      resetsAttempt = true
      resetsRetainedPrefix = false
      lineJumpCount = (lineScroll?.firstRetainedWordIndex ?? 0) > 0 ? 1 : 0
      wordReflow = .init()
      latestActiveTop = nil
      hasPendingWordUpdate = false
      if let lineScroll { lineScroll.caretMotion?.prepare(attemptID: lineScroll.attemptID) }
    }
    if prefixChanged, !attemptChanged {
      stopLineScroll()
      previousTargetTop = 0
      resetsAttempt = true
      // Source lineJump keeps the immediate anchor, or the smooth anchor
      // sampled before deletion. Rebuilding visible text is not a new word.
      resetsRetainedPrefix = true
      hasPendingWordUpdate = false
    }
    if layoutChanged || (wrapperChanged && lineScroll?.centersActiveLine == true) {
      stopLineScroll(); wordReflow = .init()
      lineScroll?.caretMotion?.resetLayout()
    }
    // Font-family application only remeasures. Source wrapper/config events,
    // font size and actual viewport width changes own forced centering.
    recentersLine = recentersLine || structuralLayoutChanged || wrapperChanged || attemptChanged
      || (self.font != font && lineScroll?.wrapperRevision == nil)
      || (self.lineScroll?.centersActiveLine == false && lineScroll?.centersActiveLine == true)
    self.lineScroll = lineScroll
    self.customGeometry = customGeometry
    self.text = text
    self.characterOffset = characterOffset
    self.font = font
    self.lineSpacing = lineSpacing
    self.isRightToLeft = isRightToLeft
    // Preserve a real text update across coalesced settings/layout callbacks.
    // Turning Slow Timer on alone must not simulate updateWordLetters.
    hasPendingWordUpdate = hasPendingWordUpdate || (textChanged && !prefixChanged)
    if needsFollow { scheduleFollow() }
  }

  override func layout() {
    super.layout()
    if bounds.width != lastWidth {
      lastWidth = bounds.width
      stopLineScroll()
      lineScroll?.caretMotion?.resetLayout()
      recentersLine = true
      scheduleFollow()
    }
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil {
      cancelCaretMotion()
      stopLineScroll()
      wordReflow = .init()
      latestActiveTop = nil
      hasPendingWordUpdate = false
    }
    super.viewWillMove(toSuperview: newSuperview)
  }

  func stopLineScroll(resetOverlap: Bool = true) {
    lineScrollTimer?.invalidate()
    lineScrollTimer = nil
    animatedTarget = nil
    lineScrollAnimation = nil
    animatedScrollView = nil
    pendingRetirement = nil
    if resetOverlap { lineScrollOverlap = .init() }
  }

  func cancelCaretMotion() {
    lineScroll?.caretMotion?.cancel(at: ProcessInfo.processInfo.systemUptime)
  }

  private func scheduleFollow() {
    guard !isFollowScheduled else { return }
    isFollowScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isFollowScheduled = false
      self.followCurrentGlyph()
    }
  }

  private func followCurrentGlyph() {
    if let lineScroll { followActiveWord(lineScroll); return }
    guard customGeometry == nil else { return }
    guard let characterOffset, bounds.width > 0, let scrollView = enclosingScrollView,
      let documentView = scrollView.documentView,
      let rect = PromptCaretLayout.rect(
        in: text, characterOffset: characterOffset, containerSize: bounds.size,
        font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
    else { return }
    let verticalMargin = min(rect.height, 28)
    let top = max(bounds.minY, rect.minY - verticalMargin)
    let bottom = min(bounds.maxY, rect.maxY + verticalMargin)
    let target = CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
    guard !scrollView.contentView.documentVisibleRect.contains(convert(target, to: documentView))
    else { return }
    _ = scrollToVisible(target)
  }

  private func followActiveWord(_ context: PromptLineScrollContext) {
    let prefixWasRebuilt = resetsRetainedPrefix
    resetsRetainedPrefix = false
    // Apply the prefix's coordinate reset first, then process any real text
    // update that arrived in the same run-loop turn against the retained anchor.
    let wordWasUpdated = hasPendingWordUpdate && !prefixWasRebuilt
    if !prefixWasRebuilt { hasPendingWordUpdate = false }
    guard let scroll = enclosingScrollView, let document = scroll.documentView,
      let wordID = context.activeWordID else { stopLineScroll(); return }
    let requestsCenter = recentersLine && context.centersActiveLine && !prefixWasRebuilt
    let words = requestsCenter && context.onRetire != nil ? context.words : context.activeWordID == previousWordID
      ? (wordWasUpdated && context.followsWordReflow ? context.words : [])
      : (context.onRetire == nil ? [] : context.words)
    let measured: PromptLineScrollGeometry?
    if let customGeometry {
      measured = customGeometry.measure(wordID, previousWordID, customGeometry.caretGlyphID, words)
    } else if let offset = context.characterOffsets[wordID] {
      measured = PromptLineScrollGeometry.measure(in: text, activeOffset: offset,
        previousOffset: previousWordID.flatMap { context.characterOffsets[$0] },
        width: bounds.width, font: font, lineSpacing: lineSpacing, rightToLeft: isRightToLeft,
        caretOffset: characterOffset, words: words,
        characterOffsets: context.characterOffsets)
    } else { measured = nil }
    guard let geometry = measured
    else { stopLineScroll(); wordReflow = .init(); latestActiveTop = nil; return }
    let documentOrigin = convert(CGPoint.zero, to: document).y
    let activeVisibleTop = documentOrigin + geometry.activeTop - scroll.contentView.bounds.minY
    latestActiveTop = geometry.activeTop
    let wordDidChange = context.activeWordID != previousWordID
    if !prefixWasRebuilt && (wordDidChange || recentersLine || wordReflow.baselineTop == nil) {
      wordReflow.anchor(at: activeVisibleTop)
    }
    let reflowFrom = wordReflow.jumpFromTop(afterUpdate: activeVisibleTop,
      enabled: wordWasUpdated && context.followsWordReflow
        && context.activeWordID == previousWordID && !recentersLine && !prefixWasRebuilt,
      transitioning: lineScrollAnimation != nil)
    let reflowHideBound = reflowFrom.map { $0 + scroll.contentView.bounds.minY - documentOrigin }
    let activeWordIndex = context.words.first(where: { $0.glyphID == wordID })?.index
    let centerHideBound = requestsCenter
      ? activeWordIndex.flatMap { geometry.recenterHideBound(before: $0) } : nil
    var retirement: PromptWordRetirement?
    var reflowCanAdvance = false
    if !prefixWasRebuilt && (centerHideBound != nil || reflowHideBound != nil || context.activeWordID != previousWordID
      && geometry.previousWordTop.map({ geometry.activeTop > $0 }) == true) {
      if lineJumpCount > 0 || centerHideBound != nil,
        let activeWordIndex,
        let boundary = geometry.retirementBoundary(before: activeWordIndex, hideBound: centerHideBound ?? reflowHideBound),
        boundary > context.firstRetainedWordIndex {
        retirement = .init(attemptID: context.attemptID, firstRetainedWordIndex: boundary)
        reflowCanAdvance = true
      }
      lineJumpCount += 1
    }
    var top = recentersLine && !context.centersActiveLine ? previousTargetTop
      : geometry.targetTop(previousTarget: previousTargetTop, recenter: recentersLine)
    if let reflowHideBound {
      // The source's first jump, and later jumps without a removable prefix,
      // only advance its line counter. They do not start a scroll animation.
      top = reflowCanAdvance ? max(previousTargetTop, reflowHideBound) : previousTargetTop
    }
    let startsJump = retirement != nil
    if startsJump {
      top = lineScrollOverlap.begin(from: centerHideBound == nil ? previousTargetTop : 0,
        rowHeight: geometry.activeRowHeight)
    } else if centerHideBound != nil {
      // Forced centering with no removable prefix only increments the source
      // line counter. A previous token's internal rows must not cause motion.
      top = previousTargetTop
    }
    // SwiftUI can wrap a single long token across multiple native rows. Keep
    // its caret reachable without the legacy extra-margin early advance.
    if prefixWasRebuilt {
      // The source resets words.marginTop to zero after deleting the prefix;
      // it does not center the remaining active row, even after multirow reflow.
      top = 0
    } else if centerHideBound == nil, let bottom = geometry.caretBottom {
      top = max(top, bottom - scroll.contentView.bounds.height)
    }
    if !prefixWasRebuilt { previousWordID = wordID }
    previousTargetTop = top
    recentersLine = false
    let region = convert(CGRect(x: 0, y: top, width: 1, height: scroll.contentView.bounds.height), to: document)
    var proposed = scroll.contentView.bounds
    proposed.origin.y = region.minY
    let target = scroll.contentView.constrainBoundsRect(proposed).origin
    let immediate = (resetsAttempt && centerHideBound == nil) || !context.smoothScroll || context.reducesMotion
    resetsAttempt = false
    if startsJump {
      context.caretMotion?.lineJump(to: -geometry.activeRowHeight * CGFloat(lineScrollOverlap.pendingJumps),
        duration: immediate ? 0 : PromptLineScrollMotion.duration,
        at: ProcessInfo.processInfo.systemUptime)
    }
    move(scroll, to: target, immediately: immediate, frameRate: context.frameRate,
      retirement: retirement, onRetire: context.onRetire, startsJump: startsJump,
      preservesReflowAnchor: startsJump || prefixWasRebuilt)
    if prefixWasRebuilt && (hasPendingWordUpdate || wordDidChange || wordReflow.baselineTop == nil) {
      scheduleFollow()
    }
  }

  private func move(_ scroll: NSScrollView, to target: CGPoint, immediately: Bool, frameRate: Int,
    retirement: PromptWordRetirement?, onRetire: ((PromptWordRetirement) -> Void)?, startsJump: Bool,
    preservesReflowAnchor: Bool) {
    let interval = PromptLineScrollMotion.frameInterval(frameRate: frameRate,
      displayFrameRate: window?.screen?.maximumFramesPerSecond ?? 60)
    // A new word animation replaces the old one. Its canceled promise never
    // completes; only this jump's captured prefix owns the eventual callback.
    var completion = startsJump ? nil : pendingRetirement
    if let retirement, let onRetire,
      retirement.firstRetainedWordIndex > (completion?.value.firstRetainedWordIndex ?? 0) {
      completion = (retirement, onRetire)
    }
    if !immediately, !startsJump, animatedTarget == target {
      pendingRetirement = completion
      if lineScrollTimer?.timeInterval != interval { scheduleLineScrollTimer(interval: interval) }
      return
    }
    stopLineScroll(resetOverlap: false)
    pendingRetirement = completion
    let clip = scroll.contentView
    let from = clip.bounds.origin
    guard from != target || startsJump && !immediately else {
      reportCaretScroll(scroll)
      lineScrollOverlap = .init()
      completeRetirement(); return
    }
    if immediately {
      clip.scroll(to: target)
      scroll.reflectScrolledClipView(clip)
      reportCaretScroll(scroll)
      if !preservesReflowAnchor { anchorWordReflow() }
      lineScrollOverlap = .init()
      completeRetirement()
      return
    }
    animatedTarget = target
    animatedScrollView = scroll
    lineScrollAnimation = (from, target,
      ProcessInfo.processInfo.systemUptime - PromptLineScrollMotion.autoplayLead)
    scheduleLineScrollTimer(interval: interval)
  }

  private func scheduleLineScrollTimer(interval: TimeInterval) {
    lineScrollTimer?.invalidate()
    let timer = Timer(timeInterval: interval, target: PromptLineScrollTimerTarget(owner: self),
      selector: #selector(PromptLineScrollTimerTarget.tick(_:)), userInfo: nil, repeats: true)
    lineScrollTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  fileprivate func advanceLineScroll(_ timer: Timer) {
    guard timer === lineScrollTimer, let animation = lineScrollAnimation,
      let scroll = animatedScrollView, enclosingScrollView === scroll
    else { timer.invalidate(); return }
    let elapsed = ProcessInfo.processInfo.systemUptime - animation.started
    let progress = PromptLineScrollMotion.progress(elapsed: elapsed)
    let clip = scroll.contentView
    clip.scroll(to: .init(x: animation.from.x + (animation.target.x - animation.from.x) * progress,
      y: animation.from.y + (animation.target.y - animation.from.y) * progress))
    scroll.reflectScrolledClipView(clip)
    reportCaretScroll(scroll)
    if elapsed >= PromptLineScrollMotion.duration {
      let completion = pendingRetirement
      lineScroll?.caretMotion?.wordsDidFinish(at: ProcessInfo.processInfo.systemUptime)
      stopLineScroll()
      anchorWordReflow()
      if let completion { completion.notify(completion.value) }
    }
  }

  private func completeRetirement() {
    let completion = pendingRetirement
    pendingRetirement = nil
    if let completion {
      lineScroll?.caretMotion?.wordsDidFinish(at: ProcessInfo.processInfo.systemUptime)
      completion.notify(completion.value)
    }
  }

  private func reportCaretScroll(_ scroll: NSScrollView) {
    guard let document = scroll.documentView else { return }
    lineScroll?.caretMotion?.reportProgrammaticScroll(
      scroll.contentView.bounds.minY - convert(CGPoint.zero, to: document).y)
  }

  private func anchorWordReflow() {
    guard let latestActiveTop, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
    wordReflow.anchor(at: convert(CGPoint(x: 0, y: latestActiveTop), to: document).y
      - scroll.contentView.bounds.minY)
  }
}

@MainActor private final class PromptLineScrollTimerTarget: NSObject {
  private weak var owner: PromptAutoScrollView?
  init(owner: PromptAutoScrollView) { self.owner = owner }
  @objc func tick(_ timer: Timer) {
    guard let owner else { timer.invalidate(); return }
    owner.advanceLineScroll(timer)
  }
}

/// A separate, code-drawn caret layer. TextKit computes each target glyph's
/// frame from the same attributed text and wrapping width shown by SwiftUI.
struct PromptCaretOverlay: NSViewRepresentable {
  let text: AttributedString
  let mainCharacterOffset: Int?
  let mainStyle: TypingCaretStyle
  let paceCharacterOffset: Int?
  let paceStyle: TypingCaretStyle
  let font: NSFont
  let lineSpacing: CGFloat
  let isRightToLeft: Bool
  let accent: Color
  let motion: SmoothCaretMotion
  var paceFrame: (() -> PromptPaceCaretInterpolation?)? = nil
  var reducesPaceMotion = false
  let coordinator: PromptCaretMotionCoordinator
  let attemptID: UUID
  var firstRetainedWordIndex = 0
  var latestInput: (() -> PromptCaretInputIdentity)? = nil
  var latestGlyphID: (() -> Int?)? = nil
  var latestRendering: (() -> PromptRendering)? = nil
  var mainPresentation: (() -> PromptCaretBlinkPresentation)? = nil
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

  func makeNSView(context: Context) -> PromptCaretNativeView { PromptCaretNativeView() }

  func updateNSView(_ view: PromptCaretNativeView, context: Context) {
    view.update(.init(text: text, mainOffset: mainCharacterOffset, paceOffset: paceCharacterOffset,
      mainStyle: mainStyle, paceStyle: paceStyle, font: font, lineSpacing: lineSpacing,
      rightToLeft: isRightToLeft, accent: accent, motion: motion,
      reducesMotion: reducesPaceMotion || systemReduceMotion,
      frameRate: animationFrameRate, attemptID: attemptID, coordinator: coordinator,
      firstRetainedWordIndex: firstRetainedWordIndex,
      latestInput: latestInput, latestGlyphID: latestGlyphID,
      latestRendering: latestRendering, paceFrame: paceFrame, mainPresentation: mainPresentation))
  }

  static func dismantleNSView(_ view: PromptCaretNativeView, coordinator: ()) {
    view.stop()
  }
}

struct PromptCaretMarkerView: View {
  let style: TypingCaretStyle
  let accent: Color
  let rect: CGRect

  var body: some View {
    let width = max(1, rect.width)
    let height = max(1, rect.height)
    ZStack {
      switch style {
      case .off:
        EmptyView()
      case .bar:
        Rectangle()
          .fill(accent)
          .frame(width: 2, height: height * 0.88)
      case .underline:
        Rectangle()
          .fill(accent)
          .frame(width: width, height: 2)
          .offset(y: height * 0.5 - 1)
      case .outline:
        RoundedRectangle(cornerRadius: max(2, height * 0.12))
          .stroke(accent, lineWidth: 2)
          .frame(width: width, height: height)
      case .block:
        RoundedRectangle(cornerRadius: max(2, height * 0.12))
          .fill(accent.opacity(0.62))
          .frame(width: width, height: height)
      case .carrot:
        CarrotCaretShape()
          .fill(accent)
          .frame(width: max(10, width * 0.85), height: max(13, height * 0.75))
      case .banana:
        BananaCaretShape()
          .stroke(accent, style: StrokeStyle(lineWidth: max(2, height * 0.13), lineCap: .round))
          .frame(width: max(12, width * 0.95), height: max(13, height * 0.75))
      case .monkey:
        MonkeyCaretMark(accent: accent)
          .frame(width: max(12, width * 0.9), height: max(12, height * 0.72))
      }
    }
    .frame(width: width, height: height)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct CarrotCaretShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.24))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.24))
    path.closeSubpath()
    return path
  }
}

private struct BananaCaretShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.14))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.18),
      control: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY + rect.height * 0.15))
    return path
  }
}

private struct MonkeyCaretMark: View {
  let accent: Color

  var body: some View {
    ZStack {
      Circle().fill(accent)
      HStack(spacing: 3) {
        Circle().fill(.primary.opacity(0.72))
        Circle().fill(.primary.opacity(0.72))
      }
      .frame(height: 3)
    }
  }
}

enum PromptCaretLayout {
  static func rect(
    in attributedText: AttributedString,
    characterOffset: Int,
    containerSize: CGSize,
    font: NSFont,
    lineSpacing: CGFloat,
    isRightToLeft: Bool = false
  ) -> CGRect? {
    guard containerSize.width > 0, characterOffset >= 0 else { return nil }
    let storage = preparedStorage(in: attributedText, font: font,
      lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
    guard storage.length > 0 else { return nil }

    let layoutManager = NSLayoutManager()
    let container = NSTextContainer(
      size: CGSize(width: containerSize.width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layoutManager.addTextContainer(container)
    storage.addLayoutManager(layoutManager)
    layoutManager.ensureLayout(for: container)

    let string = storage.string
    func glyphRect(at offset: Int) -> CGRect? {
      guard offset >= 0, offset < string.count else { return nil }
      let start = string.index(string.startIndex, offsetBy: offset)
      let end = string.index(after: start)
      let characterRange = NSRange(start..<end, in: string)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: characterRange, actualCharacterRange: nil)
      guard glyphRange.length > 0 else { return nil }
      return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).integral
    }

    guard let rect = glyphRect(at: characterOffset) else { return nil }
    let characterIndex = string.index(string.startIndex, offsetBy: characterOffset)
    if string[characterIndex].isWhitespace,
      let nextRect = glyphRect(at: characterOffset + 1),
      nextRect.minY > rect.minY
    {
      return nextRect
    }
    return rect
  }

  static func rect(in attributedText: AttributedString, utf16Range: NSRange,
    containerSize: CGSize, font: NSFont, lineSpacing: CGFloat, isRightToLeft: Bool = false,
    followsWrappedWhitespace: Bool = true) -> CGRect? {
    guard containerSize.width > 0, utf16Range.location >= 0, utf16Range.length > 0 else { return nil }
    let storage = preparedStorage(in: attributedText, font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
    guard utf16Range.location < storage.length, utf16Range.length <= storage.length - utf16Range.location else { return nil }
    let layout = NSLayoutManager(), container = NSTextContainer(size: .init(width: containerSize.width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0; layout.addTextContainer(container); storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    let glyphs = layout.glyphRange(forCharacterRange: utf16Range, actualCharacterRange: nil)
    guard glyphs.length > 0 else { return nil }
    let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).integral
    if followsWrappedWhitespace,
      (storage.string as NSString).substring(with: utf16Range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      NSMaxRange(utf16Range) < storage.length {
      let next = layout.glyphRange(forCharacterRange: .init(location: NSMaxRange(utf16Range), length: 1), actualCharacterRange: nil)
      let nextRect = layout.boundingRect(forGlyphRange: next, in: container).integral
      if nextRect.minY > rect.minY { return nextRect }
    }
    return rect
  }

  /// Shared font and paragraph preparation keeps viewport and caret wrapping aligned.
  static func preparedStorage(in attributedText: AttributedString, font: NSFont,
    lineSpacing: CGFloat, isRightToLeft: Bool) -> NSTextStorage {
    let storage = NSTextStorage(attributedString: NSAttributedString(attributedText))
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.alignment = isRightToLeft ? .right : .left
    paragraphStyle.baseWritingDirection = isRightToLeft ? .rightToLeft : .leftToRight
    let fullRange = NSRange(location: 0, length: storage.length)
    // The AppKit bridge supplies a 12 pt fallback for SwiftUI's environment font.
    let swiftUIFontKey = NSAttributedString.Key("SwiftUI.Font")
    var hintFontRanges: [NSRange] = []
    storage.enumerateAttribute(swiftUIFontKey, in: fullRange) { explicitFont, range, _ in
      if explicitFont != nil { hintFontRanges.append(range) }
    }
    storage.addAttribute(.font, value: font, range: fullRange)
    let hintFont = NSFont.monospacedSystemFont(
      ofSize: max(9, font.pointSize * 0.48), weight: .semibold)
    for range in hintFontRanges { storage.addAttribute(.font, value: hintFont, range: range) }
    storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
    return storage
  }
}

extension PracticeFont {
  func nsFont(
    size: CGFloat, installedFontName: String = "", language: TypingLanguage = .english,
    resolver: NativePracticeFont.Resolver = .init(), purpose: NativePracticeFont.Resolver.Purpose = .practice
  ) -> NSFont {
    if let name = resolver.postScriptName(for: installedFontName, purpose: purpose),
      let font = NSFont(name: name, size: size) {
      return LanguagePracticeFontFallback.applying(to: font, language: language)
    }
    let systemFont: NSFont = switch self {
    case .monospaced:
      NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    case .rounded:
      nativeFont(size: size, design: .rounded)
    case .serif:
      nativeFont(size: size, design: .serif)
    case .defaultSystem:
      NSFont.systemFont(ofSize: size, weight: .medium)
    }
    return LanguagePracticeFontFallback.applying(to: systemFont, language: language)
  }

  private func nativeFont(size: CGFloat, design: NSFontDescriptor.SystemDesign) -> NSFont {
    let descriptor = NSFont.systemFont(ofSize: size, weight: .medium).fontDescriptor
    guard let designedDescriptor = descriptor.withDesign(design) else {
      return NSFont.systemFont(ofSize: size, weight: .medium)
    }
    return NSFont(descriptor: designedDescriptor, size: size)
      ?? NSFont.systemFont(ofSize: size, weight: .medium)
  }
}
