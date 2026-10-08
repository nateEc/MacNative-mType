import AppKit

/// Native word boxes, not paragraphs: a Return owns a following row whose
/// indentation is independent of both the words tape and the pace marker.
/// This component deliberately does not own vertical retirement or a clock.
@MainActor final class TapeNewlineTextLayout {
  private final class Word {
    let descriptor: TapePromptWord
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude))
    let storage = NSTextStorage()
    let characterRanges: [Int: NSRange]
    let row: Int
    let inline: CGFloat
    let precedingBreak: Int?
    let bounds: CGRect

    init(descriptor: TapePromptWord, prepared: NSAttributedString,
      ranges: [NSRange], characters: [Character], row: Int, inline: CGFloat, precedingBreak: Int?) {
      self.descriptor = descriptor; self.row = row; self.inline = inline
      self.precedingBreak = precedingBreak
      var mapping: [Int: NSRange] = [:]
      for offset in descriptor.characters where ranges.indices.contains(offset) && characters[offset] != "\n" {
        let fragment = prepared.attributedSubstring(from: ranges[offset])
        mapping[offset] = NSRange(location: storage.length, length: fragment.length)
        storage.append(fragment)
      }
      characterRanges = mapping
      container.lineFragmentPadding = 0
      manager.addTextContainer(container); storage.addLayoutManager(manager)
      manager.ensureLayout(for: container)
      bounds = TapePromptTextStorage.advanceRect(manager.glyphRange(forCharacterRange:
        NSRange(location: 0, length: storage.length), actualCharacterRange: nil), manager: manager, container: container)
    }

    func rect(_ offset: Int, minimum: Int) -> CGRect? {
      var original: CGRect?
      guard characterRanges[offset] != nil else { return nil }
      for index in stride(from: offset, through: max(minimum, descriptor.characters.lowerBound), by: -1) {
        guard let range = characterRanges[index] else { continue }
        let rect = TapePromptTextStorage.advanceRect(manager.glyphRange(forCharacterRange: range,
          actualCharacterRange: nil), manager: manager, container: container)
        if index == offset { original = rect }
        if rect.width > 0, rect.height > 0 { return rect }
      }
      return original
    }

    func width(before offset: Int) -> CGFloat {
      let ranges = characterRanges.filter { $0.key < offset }.values
      guard let first = ranges.min(by: { $0.location < $1.location }),
        let last = ranges.max(by: { $0.location < $1.location }) else { return 0 }
      let range = NSUnionRange(first, last)
      return TapePromptTextStorage.advanceRect(manager.glyphRange(forCharacterRange: range,
        actualCharacterRange: nil), manager: manager, container: container).width
    }
  }

  private var words: [Word] = []
  private var wordByOffset: [Int: Int] = [:]
  private var text = AttributedString()
  private var descriptors: [TapePromptWord] = []
  private var font: NSFont?
  private var rightToLeft = false
  private var indents: [Int: PromptCaretChannel] = [:]
  private var characters: [Character] = []
  private var totalWidth: CGFloat = 0
  private var maximumRowWidth: CGFloat = 0
  private(set) var leadingEdge: CGFloat = 0
  private(set) var metrics = TapePromptLayoutMetrics(contentHeight: 0, rowHeight: 0)
  private(set) var wordMetrics: [TapeNewlineWordMetric] = []
  var isAnimating: Bool { indents.values.contains { $0.isAnimatingTape } }
  var contentWidth: CGFloat { rightToLeft ? leadingEdge : (words.map { frame($0).maxX }.max() ?? 0) }

  func configure(text: AttributedString, words descriptors: [TapePromptWord], font: NSFont,
    rightToLeft: Bool, resets: Bool) {
    if resets { indents = [:] }
    guard self.text != text || self.descriptors != descriptors || self.font != font
      || self.rightToLeft != rightToLeft else { return }
    self.text = text; self.descriptors = descriptors; self.font = font; self.rightToLeft = rightToLeft
    let prepared = TapePromptTextStorage.prepare(text, font: font, rightToLeft: rightToLeft)
    let string = prepared.string
    characters = Array(string)
    let ranges = string.indices.map { NSRange($0..<string.index(after: $0), in: string) }
    words = []; wordMetrics = []; wordByOffset = [:]
    var row = 0, inline: CGFloat = 0, precedingBreak: Int?
    // Native spacing is kept explicit. CSS pixel/line-box equivalence remains
    // a separate acceptance requirement; no upstream font/icon asset is used.
    let gap = font.pointSize * 0.6
    var rowHeight = NSLayoutManager().defaultLineHeight(for: font)
    for descriptor in descriptors {
      let word = Word(descriptor: descriptor, prepared: prepared, ranges: ranges,
        characters: characters, row: row, inline: inline, precedingBreak: precedingBreak)
      let slot = words.count
      words.append(word)
      for offset in word.characterRanges.keys { wordByOffset[offset] = slot }
      let markerWidth = descriptor.newlineCharacterOffset.map {
        descriptor.incorrectNewline ? 0 : (word.rect($0, minimum: $0)?.width ?? 0)
      }
      wordMetrics.append(.init(index: descriptor.index, width: word.bounds.width, gap: gap, newlineWidth: markerWidth))
      rowHeight = max(rowHeight, word.bounds.height)
      inline += word.bounds.width + gap
      if descriptor.newlineCharacterOffset != nil {
        row += 1; inline = 0; precedingBreak = descriptor.glyphID
      }
    }
    let liveBreaks = Set(descriptors.filter { $0.newlineCharacterOffset != nil }.map(\.glyphID))
    indents = indents.filter { liveBreaks.contains($0.key) }
    rowHeight += 12
    let rows = (words.last?.row ?? -1) + 1
    metrics = .init(contentHeight: CGFloat(rows) * rowHeight, rowHeight: rowHeight)
    totalWidth = wordMetrics.reduce(0) { $0 + $1.width + $1.gap }
    maximumRowWidth = words.map { $0.inline + $0.bounds.width }.max() ?? 0
    updateOrigin()
  }

  func plan(at offset: Int, viewportWidth: CGFloat) -> TapeNewlinePlan {
    let active = word(at: offset)?.descriptor.index ?? words.last?.descriptor.index ?? 0
    return .measure(words: wordMetrics, active: active, viewportWidth: viewportWidth)
  }

  func request(_ plan: TapeNewlinePlan, duration: TimeInterval, at time: TimeInterval) {
    for word in words {
      guard let target = plan.indents[word.descriptor.index] else { continue }
      var channel = indents[word.descriptor.glyphID] ?? .init()
      channel.tapeScroll(to: target, at: time, duration: duration)
      indents[word.descriptor.glyphID] = channel
    }
    updateOrigin()
  }

  func sample(at time: TimeInterval) {
    for key in Array(indents.keys) { indents[key]?.sample(at: time) }
    updateOrigin()
  }

  private func updateOrigin() {
    // Keep RTL glyphs inside the native drawing view, not at negative local
    // coordinates that AppKit clips before the parent's tape transform.
    leadingEdge = rightToLeft ? max(totalWidth, maximumRowWidth + (indents.values.map(\.tapeMargin).max() ?? 0)) : 0
  }

  private func word(at offset: Int) -> Word? {
    wordByOffset[offset].map { words[$0] }
  }
  private func frame(_ word: Word) -> CGRect {
    let indent = word.precedingBreak.flatMap { indents[$0]?.tapeMargin } ?? 0
    let x = word.inline + indent
    return .init(x: rightToLeft ? leadingEdge - x - word.bounds.width : x,
      y: CGFloat(word.row) * metrics.rowHeight, width: word.bounds.width, height: word.bounds.height)
  }
  func wordRect(at offset: Int) -> CGRect? { word(at: offset).map { frame($0) } }
  func glyphRect(at offset: Int, minimumOffset: Int) -> CGRect? {
    guard let word = word(at: offset), let rect = word.rect(offset, minimum: minimumOffset) else { return nil }
    let origin = frame(word).origin
    return rect.offsetBy(dx: origin.x - word.bounds.minX, dy: origin.y - word.bounds.minY)
  }
  func advance(at offset: Int, mode: PracticeTapeMode, viewportWidth: CGFloat) -> CGFloat {
    guard let word = word(at: offset) else { return 0 }
    let before = plan(at: offset, viewportWidth: viewportWidth).beforeActive
    guard mode == .letter, offset > word.descriptor.characters.lowerBound else { return before }
    var within = word.width(before: offset)
    if word.rect(offset, minimum: offset)?.width == 0 {
      for index in stride(from: offset - 1, through: word.descriptor.characters.lowerBound, by: -1) {
        if let rect = word.rect(index, minimum: index), rect.width > 0 { within -= rect.width; break }
      }
    }
    return before + within
  }
  func direction(at offset: Int, perGlyph: Bool, fallback: Bool) -> Bool {
    guard characters.indices.contains(offset), let word = word(at: offset) else { return fallback }
    let string = perGlyph ? String(characters[offset]) : word.storage.string
    return PracticeTapePolicy.isRightToLeft(string, fallback: fallback)
  }
  func draw(in dirtyRect: CGRect) {
    for word in words {
      let frame = frame(word)
      guard frame.intersects(dirtyRect) else { continue }
      let origin = CGPoint(x: frame.minX - word.bounds.minX, y: frame.minY - word.bounds.minY)
      let range = NSRange(location: 0, length: word.manager.numberOfGlyphs)
      word.manager.drawBackground(forGlyphRange: range, at: origin)
      word.manager.drawGlyphs(forGlyphRange: range, at: origin)
    }
  }
}
