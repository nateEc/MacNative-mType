import AppKit

struct TapeNewlineWordMetric: Equatable {
  let index: Int
  let width: CGFloat
  let gap: CGFloat
  var newlineWidth: CGFloat? = nil
}

struct TapeNewlinePlan {
  let beforeActive: CGFloat
  let indents: [Int: CGFloat]

  static func measure(words: [TapeNewlineWordMetric], active: Int, viewportWidth: CGFloat) -> Self {
    let breaks = words.filter { $0.newlineWidth != nil }
    let upcoming = breaks.filter { $0.index >= active }
    let last = upcoming.prefix(2).last?.index ?? active - 1
    var advance: CGFloat = 0, before: CGFloat = 0, indents: [Int: CGFloat] = [:]
    for word in words where word.index <= last {
      advance += word.width + word.gap
      if word.index < active { before = advance }
      if let markerWidth = word.newlineWidth {
        advance -= markerWidth + word.gap
        if word.index < active { before = advance }
        let limit = viewportWidth * 3
        indents[word.index] = min(advance, limit)
        if advance >= limit {
          if word.index < last, let next = breaks.first(where: { $0.index > word.index }) {
            indents[next.index] = limit
          }
          break
        }
      }
    }
    return .init(beforeActive: before, indents: indents)
  }
}

struct TapePromptWord: Equatable {
  let index: Int
  let glyphID: Int
  let characters: Range<Int>
  var newlineCharacterOffset: Int? = nil
  var incorrectNewline = false
  var hasStructuralNewline = false
  var isRemoved = false
  /// Canonical control cells, distinct from the unmapped structural LF.
  var controlCharacterOffsets: [Int: Character] = [:]
  var ownsNewline: Bool { hasStructuralNewline || newlineCharacterOffset != nil }
}

struct TapePromptLayoutMetrics: Equatable {
  let contentHeight: CGFloat
  let rowHeight: CGFloat
}
