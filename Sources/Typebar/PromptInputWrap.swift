import AppKit
import SwiftUI

/// Reads the mounted prompt's current width synchronously; no queued geometry
/// notification can reattach an old attempt or retain a removed text view.
@MainActor final class PromptInputWrapLayout {
  nonisolated init() {}
  weak var view: NSView?
  var width: CGFloat? {
    guard let view, view.window != nil, view.superview != nil,
      view.bounds.width.isFinite, view.bounds.width > 0 else { return nil }
    return view.bounds.width
  }
}

struct PromptInputWrapOverlay: NSViewRepresentable {
  let layout: PromptInputWrapLayout
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    layout.view = view
    return view
  }
  func updateNSView(_ view: NSView, context: Context) { layout.view = view }
}

enum PromptInputWrapGeometry {
  /// Probe the already-rendered letters and append only missing input units.
  /// Hints, retired prefixes, replacement text, RTL, and font preparation are
  /// shared with the actual prompt, not a projected mutation of the session.
  static func rejects(
    session: TypingSession, candidate: [UInt16], rendering: PromptRendering,
    width: CGFloat, font: NSFont, lineSpacing: CGFloat, isRightToLeft: Bool
  ) -> Bool {
    guard width.isFinite, width > 0,
      let word = session.promptWordPresentations.first(where: { $0.phase == .active })
    else { return false }
    let glyphs = session.promptGlyphs
    var owned = Array(word.range) + word.extraGlyphIndices
    // Return belongs to the display word; a space commit does not.
    if glyphs.indices.contains(word.range.upperBound), glyphs[word.range.upperBound].character == "\n" {
      owned.append(word.range.upperBound)
    }
    let offsets = owned.compactMap { rendering.glyphCharacterOffsets[$0] }
    guard let start = offsets.min(), let last = offsets.max() else { return false }
    let end = rendering.glyphCharacterOffsets.values.filter { $0 > last }.min()
      ?? rendering.text.characters.count
    let missing = candidate.count - session.promptInputWrapLetterUnitCount
    guard missing > 0 else { return false }
    let suffix = String(decoding: candidate.suffix(missing), as: UTF16.self)
    let append = suffix.map {
      PromptControlCharacterPresentation.plan(for: .init(character: $0, state: .extra), style: .off).text
    }.joined()
    var extended = rendering.text
    // Native extras precede the structural Return marker, so the probe must
    // use that same insertion point rather than create a new source line.
    let appendOffset = glyphs.indices.contains(word.range.upperBound)
      && glyphs[word.range.upperBound].character == "\n"
      ? rendering.glyphCharacterOffsets[word.range.upperBound] ?? end : end
    let insertion = extended.characters.index(extended.startIndex, offsetBy: appendOffset)
    extended.insert(AttributedString(append), at: insertion)
    guard let before = wordRect(text: rendering.text, start: start, end: end, width: width,
      font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft),
      let after = wordRect(text: extended, start: start, end: end + append.count, width: width,
        font: font, lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
    else { return false }
    return after.minY > before.minY || after.height > before.height
  }

  private static func wordRect(text: AttributedString, start: Int, end: Int,
    width: CGFloat, font: NSFont, lineSpacing: CGFloat, isRightToLeft: Bool) -> CGRect? {
    let storage = PromptCaretLayout.preparedStorage(in: text, font: font,
      lineSpacing: lineSpacing, isRightToLeft: isRightToLeft)
    let string = storage.string
    guard start >= 0, end > start, end <= string.count else { return nil }
    let lower = string.index(string.startIndex, offsetBy: start)
    let upper = string.index(string.startIndex, offsetBy: end)
    let manager = NSLayoutManager(), container = NSTextContainer(size: .init(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let range = manager.glyphRange(forCharacterRange: NSRange(lower..<upper, in: string), actualCharacterRange: nil)
    guard range.length > 0 else { return nil }
    // A line fragment gains trailing spacing when a *later* word wraps.
    // Compare this word's occupied lines without that trailing spacing.
    let first = manager.lineFragmentRect(forGlyphAt: range.location, effectiveRange: nil)
    var lastRange = NSRange()
    let last = manager.lineFragmentRect(forGlyphAt: NSMaxRange(range) - 1, effectiveRange: &lastRange)
    let trailingSpacing = NSMaxRange(lastRange) < manager.numberOfGlyphs ? lineSpacing : 0
    let result = CGRect(x: 0, y: first.minY, width: width,
      height: last.maxY - first.minY - trailingSpacing)
    return result.isNull ? nil : result
  }
}
