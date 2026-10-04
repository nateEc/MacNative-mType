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

private struct PromptCaretMarker: Identifiable {
  let id: String
  let characterOffset: Int
  let style: TypingCaretStyle
  let opacity: Double
}

struct PromptRendering {
  let text: AttributedString
  let glyphCharacterOffsets: [Int: Int]

  static func make(
    glyphs: [TypingPromptGlyph], indices: [Int],
    renderGlyph: (Int, TypingPromptGlyph) -> AttributedString
  ) -> Self {
    var text = AttributedString()
    var offsets: [Int: Int] = [:]
    for index in indices {
      offsets[index] = text.characters.count
      text += renderGlyph(index, glyphs[index])
    }
    return Self(text: text, glyphCharacterOffsets: offsets)
  }

  func characterOffset(forGlyphAt index: Int?) -> Int? {
    guard let index else { return nil }
    return glyphCharacterOffsets[index]
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
    isZen: Bool = false, isExtra: Bool = false, compositionReplacement: String? = nil
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

private struct PromptCaretPlacement: Identifiable {
  let marker: PromptCaretMarker
  let rect: CGRect

  var id: String { marker.id }
}

struct PromptPaceCaretInterpolation {
  let fromCharacterOffset: Int?
  let targetCharacterOffset: Int?
  let fromAfter: Bool
  let targetAfter: Bool
  let fraction: Double
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

  func makeNSView(context: Context) -> PromptAutoScrollView {
    PromptAutoScrollView()
  }

  func updateNSView(_ nsView: PromptAutoScrollView, context: Context) {
    nsView.update(
      text: text, characterOffset: characterOffset, font: font,
      lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
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

  override var isFlipped: Bool { true }

  func update(
    text: AttributedString, characterOffset: Int?, font: NSFont,
    lineSpacing: CGFloat, isRightToLeft: Bool
  ) {
    let needsFollow = self.characterOffset != characterOffset
      || self.text.characters.count != text.characters.count
      || self.font != font || self.lineSpacing != lineSpacing
      || self.isRightToLeft != isRightToLeft
    self.text = text
    self.characterOffset = characterOffset
    self.font = font
    self.lineSpacing = lineSpacing
    self.isRightToLeft = isRightToLeft
    if needsFollow { scheduleFollow() }
  }

  override func layout() {
    super.layout()
    if bounds.width != lastWidth {
      lastWidth = bounds.width
      scheduleFollow()
    }
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
}

/// A separate, code-drawn caret layer. TextKit computes each target glyph's
/// frame from the same attributed text and wrapping width shown by SwiftUI.
struct PromptCaretOverlay: View {
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
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

  var body: some View {
    GeometryReader { proxy in
      if let paceFrame {
        TimelineView(.animation(minimumInterval: reducesPaceMotion || systemReduceMotion
          ? 0.1 : AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate))) { _ in
          markerLayer(in: proxy.size, interpolation: paceFrame(), dynamicPace: true)
        }
      } else { markerLayer(in: proxy.size, interpolation: nil, dynamicPace: false) }
    }
  }

  private func markerLayer(in size: CGSize, interpolation: PromptPaceCaretInterpolation?, dynamicPace: Bool) -> some View {
    let placements = markerPlacements(in: size, interpolation: interpolation, dynamicPace: dynamicPace)
    return ZStack(alignment: .topLeading) {
        ForEach(placements) { placement in
          PromptCaretMarkerView(
            style: placement.marker.style,
            accent: accent.opacity(placement.marker.opacity),
            rect: placement.rect)
          .position(
            x: PromptCaretPlacementPolicy.horizontalAnchor(
              for: placement.rect, style: placement.marker.style,
              isRightToLeft: isRightToLeft),
            y: placement.rect.midY)
          .animation(
            placement.id == "main" ? motion.duration.map { .easeInOut(duration: $0) } : nil,
            value: placement.rect)
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private func markerPlacements(in size: CGSize, interpolation: PromptPaceCaretInterpolation?, dynamicPace: Bool) -> [PromptCaretPlacement] {
    let markers = [
      (dynamicPace ? nil : paceCharacterOffset).map {
        PromptCaretMarker(id: "pace", characterOffset: $0, style: paceStyle, opacity: 0.72)
      },
      mainCharacterOffset.map {
        PromptCaretMarker(id: "main", characterOffset: $0, style: mainStyle, opacity: 1)
      },
    ].compactMap { $0 }.filter { $0.style != .off }

    var placements = markers.compactMap { marker -> PromptCaretPlacement? in
      guard let rect = PromptCaretLayout.rect(
        in: text, characterOffset: marker.characterOffset, containerSize: size,
        font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
      else { return nil }
      return PromptCaretPlacement(marker: marker, rect: rect)
    }
    if paceStyle.drawsMarker, let interpolation, let target = interpolation.targetCharacterOffset,
      let to = PromptCaretLayout.rect(in: text, characterOffset: target, containerSize: size,
        font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft) {
      let from = interpolation.fromCharacterOffset.flatMap {
        PromptCaretLayout.rect(in: text, characterOffset: $0, containerSize: size,
          font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
      } ?? to
      let rect = PromptPaceCaretGeometry.rect(from: from, to: to,
        fromAfter: interpolation.fromAfter, toAfter: interpolation.targetAfter,
        style: paceStyle, rightToLeft: isRightToLeft, fraction: interpolation.fraction,
        reducesMotion: reducesPaceMotion || systemReduceMotion,
        afterWidth: (" " as NSString).size(withAttributes: [.font: font]).width)
      placements.insert(.init(marker: .init(id: "pace", characterOffset: target, style: paceStyle,
        opacity: 0.72), rect: rect), at: 0)
    }
    return placements
  }
}

private struct PromptCaretMarkerView: View {
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
    let storage = NSTextStorage(attributedString: NSAttributedString(attributedText))
    guard storage.length > 0 else { return nil }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.lineBreakMode = .byWordWrapping
    paragraphStyle.alignment = isRightToLeft ? .right : .left
    paragraphStyle.baseWritingDirection = isRightToLeft ? .rightToLeft : .leftToRight
    let fullRange = NSRange(location: 0, length: storage.length)
    // AttributedString's AppKit bridge supplies a 12 pt fallback even when
    // the SwiftUI Text has a larger environment font. That fallback must not
    // determine wrapping or the caret will point at the wrong line.
    let swiftUIFontKey = NSAttributedString.Key("SwiftUI.Font")
    var hintFontRanges: [NSRange] = []
    storage.enumerateAttribute(swiftUIFontKey, in: fullRange) { explicitFont, range, _ in
      if explicitFont != nil { hintFontRanges.append(range) }
    }
    storage.addAttribute(.font, value: font, range: fullRange)
    let hintFont = NSFont.monospacedSystemFont(
      ofSize: max(9, font.pointSize * 0.48), weight: .semibold)
    for range in hintFontRanges {
      storage.addAttribute(.font, value: hintFont, range: range)
    }
    storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

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
}

extension PracticeFont {
  func nsFont(
    size: CGFloat, installedFontName: String = "", language: TypingLanguage = .english
  ) -> NSFont {
    if let font = NativePracticeFont.nsFont(named: installedFontName, size: size) {
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
