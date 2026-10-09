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
    var row: Int
    var inline: CGFloat
    var precedingBreak: Int?
    let bounds: CGRect

    init(descriptor: TapePromptWord, prepared: NSAttributedString,
      ranges: [NSRange], characters: [Character], row: Int, inline: CGFloat, precedingBreak: Int?) {
      self.descriptor = descriptor; self.row = row; self.inline = inline
      self.precedingBreak = precedingBreak
      var mapping: [Int: NSRange] = [:]
      for offset in descriptor.characters where ranges.indices.contains(offset) {
        let fragment: NSAttributedString
        if let control = descriptor.controlCharacterOffsets[offset], characters[offset] == control {
          // Zen controls have no ink, but still own a native icon-sized cell.
          // Keep the shared opacity/font/decoration attributes unchanged.
          fragment = NSAttributedString(string: control == "\n" ? "↵" : "→",
            attributes: prepared.attributes(at: ranges[offset].location, effectiveRange: nil))
        } else {
          guard characters[offset] != "\n" else { continue }
          fragment = prepared.attributedSubstring(from: ranges[offset])
        }
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
  private var pendingPrefixCorrection: CGFloat = 0
  private var flow = TapeNewlineFlow()
  private var rowsByNode: [TapeNewlineFlow.Node: Int] = [:]
  private(set) var leadingEdge: CGFloat = 0
  private(set) var metrics = TapePromptLayoutMetrics(contentHeight: 0, rowHeight: 0)
  private(set) var wordMetrics: [TapeNewlineWordMetric] = []
  var isAnimating: Bool { indents.values.contains { $0.isAnimatingTape } }
  var removedWordIndices: Set<Int> { flow.removedWordIndices }
  var contentWidth: CGFloat { rightToLeft ? leadingEdge : (words.map { frame($0).maxX }.max() ?? 0) }

  func configure(text: AttributedString, words descriptors: [TapePromptWord], font: NSFont,
    rightToLeft: Bool, resets: Bool) {
    if resets { indents = [:]; pendingPrefixCorrection = 0 }
    guard resets || self.text != text || self.descriptors != descriptors || self.font != font
      || self.rightToLeft != rightToLeft else { return }
    if !resets, let first = descriptors.first, let oldFirst = self.descriptors.first,
      first.index > oldFirst.index,
      let retained = words.first(where: { $0.descriptor.index >= first.index }) {
      // Source scrollTape removes the *presented* leading filler, not the
      // mathematical width of the retired text (which may exceed the cap).
      let oldFrame = frame(retained)
      pendingPrefixCorrection = self.rightToLeft ? leadingEdge - oldFrame.maxX : oldFrame.minX
    }
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
      let markerWidth: CGFloat? = descriptor.ownsNewline ? descriptor.newlineCharacterOffset.map {
        descriptor.incorrectNewline ? 0 : (word.rect($0, minimum: $0)?.width ?? 0)
      } ?? 0 : nil
      wordMetrics.append(.init(index: descriptor.index, width: word.bounds.width, gap: gap, newlineWidth: markerWidth))
      rowHeight = max(rowHeight, word.bounds.height)
      inline += word.bounds.width + gap
      if descriptor.ownsNewline {
        row += 1; inline = 0; precedingBreak = descriptor.glyphID
      }
    }
    let liveBreaks = Set(descriptors.filter(\.ownsNewline).map(\.glyphID))
    indents = indents.filter { liveBreaks.contains($0.key) }
    rowHeight += 12
    let rows = (words.last?.row ?? -1) + 1
    metrics = .init(contentHeight: CGFloat(rows) * rowHeight, rowHeight: rowHeight)
    totalWidth = wordMetrics.reduce(0) { $0 + $1.width + $1.gap }
    maximumRowWidth = words.map { $0.inline + $0.bounds.width }.max() ?? 0
    flow.configure(words: wordMetrics, resets: resets,
      removedWords: Set(descriptors.filter(\.isRemoved).map(\.index)))
    reflowConnectedBoxes()
    updateOrigin()
  }

  func plan(at offset: Int, viewportWidth: CGFloat) -> TapeNewlinePlan {
    let active = word(at: offset)?.descriptor.index ?? words.last?.descriptor.index ?? 0
    var preview = flow
    guard let pass = preview.scroll(active: active, viewportWidth: viewportWidth,
      overflowing: { _ in false }, fillerMargin: { _ in 0 }) else {
      return .init(beforeActive: 0, indents: [:])
    }
    return .init(beforeActive: pass.beforeActive, indents: pass.indents)
  }

  /// One horizontal request sees the last presented boxes. The persistent
  /// topology, native layout and surviving filler channels change together.
  func requestScroll(at offset: Int, mode: PracticeTapeMode, viewportWidth: CGFloat,
    duration: TimeInterval, time: TimeInterval, overflowing: (Int, CGRect) -> Bool)
    -> (advance: CGFloat, compensation: CGFloat, removedWords: Set<Int>)? {
    guard let active = word(at: offset) else { return nil }
    let within = mode == .letter ? inlineAdvance(in: active, before: offset) : 0
    let frames = Dictionary(uniqueKeysWithValues: words.map { ($0.descriptor.index, frame($0)) })
    let glyphIDs = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.index, $0.glyphID) })
    let margins = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.index, indents[$0.glyphID]?.tapeMargin ?? 0) })
    guard let pass = flow.scroll(active: active.descriptor.index, viewportWidth: viewportWidth,
      overflowing: { index in frames[index].map { overflowing(index, $0) } ?? false },
      fillerMargin: { margins[$0] ?? 0 }) else { return nil }
    let liveFillers = Set(flow.nodes.filter { $0.kind == .afterNewline }.compactMap { glyphIDs[$0.index] })
    indents = indents.filter { liveFillers.contains($0.key) }
    for (index, target) in pass.indents {
      guard let id = glyphIDs[index] else { continue }
      var channel = indents[id] ?? .init()
      let correction = (pass.fillerCorrections[index] ?? 0) + pendingPrefixCorrection
      if correction != 0 { channel.shiftTapeOrigin(by: -correction) }
      channel.tapeScroll(to: target, at: time, duration: duration)
      indents[id] = channel
    }
    pendingPrefixCorrection = 0
    reflowConnectedBoxes(); updateOrigin()
    return (pass.beforeActive + within, pass.compensation, pass.removedWords)
  }

  private func reflowConnectedBoxes() {
    let byIndex = Dictionary(uniqueKeysWithValues: words.map { ($0.descriptor.index, $0) })
    let glyphIDs = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.index, $0.glyphID) })
    let gaps = Dictionary(uniqueKeysWithValues: wordMetrics.map { ($0.index, $0.gap) })
    words = []; wordByOffset = [:]; rowsByNode = [:]
    var row = 0, occupiedRow = -1, inline: CGFloat = 0, preceding: Int?
    for node in flow.nodes {
      rowsByNode[node] = row
      switch node.kind {
      case .word:
        guard let word = byIndex[node.index] else { continue }
        word.row = row; word.inline = inline; word.precedingBreak = preceding
        let slot = words.count; words.append(word)
        for offset in word.characterRanges.keys { wordByOffset[offset] = slot }
        inline += word.bounds.width + (gaps[node.index] ?? 0)
        occupiedRow = max(occupiedRow, row)
      case .beforeNewline: occupiedRow = max(occupiedRow, row)
      case .newline: row += 1; inline = 0; preceding = nil
      case .afterNewline: preceding = glyphIDs[node.index]
      }
    }
    metrics = .init(contentHeight: CGFloat(occupiedRow + 1) * metrics.rowHeight, rowHeight: metrics.rowHeight)
    totalWidth = words.reduce(0) { $0 + $1.bounds.width + (gaps[$1.descriptor.index] ?? 0) }
    maximumRowWidth = words.map { $0.inline + $0.bounds.width }.max() ?? 0
  }

  func retirementBoundary(before active: Int, hideBound: CGFloat) -> Int? {
    guard let slot = flow.nodes.firstIndex(of: .init(kind: .word, index: active)) else { return nil }
    return flow.nodes.prefix(slot).last(where: { node in
      (node.kind == .word || node.kind == .beforeNewline)
        && CGFloat(rowsByNode[node] ?? 0) * metrics.rowHeight < hideBound
    }).map { $0.index + 1 }
  }

  func request(_ plan: TapeNewlinePlan, duration: TimeInterval, at time: TimeInterval) {
    for word in words {
      guard let target = plan.indents[word.descriptor.index] else { continue }
      var channel = indents[word.descriptor.glyphID] ?? .init()
      if pendingPrefixCorrection != 0 {
        // Only the fillers visited by this scroll request are rebased. Far
        // future fillers keep their old values until their own lookahead.
        channel.shiftTapeOrigin(by: -pendingPrefixCorrection)
      }
      channel.tapeScroll(to: target, at: time, duration: duration)
      indents[word.descriptor.glyphID] = channel
    }
    pendingPrefixCorrection = 0
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
  func prefixCompensation(at offset: Int) -> CGFloat? {
    guard let word = word(at: offset) else { return nil }
    let rect = frame(word)
    return rightToLeft ? leadingEdge - rect.maxX : rect.minX
  }
  func glyphRect(at offset: Int, minimumOffset: Int) -> CGRect? {
    guard let word = word(at: offset), let rect = word.rect(offset, minimum: minimumOffset) else { return nil }
    let origin = frame(word).origin
    return rect.offsetBy(dx: origin.x - word.bounds.minX, dy: origin.y - word.bounds.minY)
  }
  func advance(at offset: Int, mode: PracticeTapeMode, viewportWidth: CGFloat) -> CGFloat {
    guard let word = word(at: offset) else { return 0 }
    let before = plan(at: offset, viewportWidth: viewportWidth).beforeActive
    return before + (mode == .letter ? inlineAdvance(in: word, before: offset) : 0)
  }
  private func inlineAdvance(in word: Word, before offset: Int) -> CGFloat {
    guard offset > word.descriptor.characters.lowerBound else { return 0 }
    var within = word.width(before: offset)
    if word.rect(offset, minimum: offset)?.width == 0 {
      for index in stride(from: offset - 1, through: word.descriptor.characters.lowerBound, by: -1) {
        if let rect = word.rect(index, minimum: index), rect.width > 0 { within -= rect.width; break }
      }
    }
    return within
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
