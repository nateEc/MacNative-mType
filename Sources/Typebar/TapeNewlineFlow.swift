import AppKit

/// Horizontal disappearance is not a vertical prefix acknowledgement.
/// These identities are process-local and do not erase prompt/input/replay.
struct PromptTapeWordRemoval: Equatable {
  let attemptID: UUID
  let wordIndices: Set<Int>
}

/// Presentation topology, not input data. A horizontally removed word leaves
/// its three structural Return boxes in place; only vertical retirement can
/// remove an entire row prefix. Identity survives text-offset rebuilds.
struct TapeNewlineFlow {
  struct Node: Equatable, Hashable {
    enum Kind: String, Decodable { case word, beforeNewline, newline, afterNewline }
    let kind: Kind
    let index: Int
  }
  struct Scroll {
    let beforeActive: CGFloat
    let indents: [Int: CGFloat]
    let fillerCorrections: [Int: CGFloat]
    let compensation: CGFloat
    let removedWords: Set<Int>
  }
  private(set) var nodes: [Node] = []
  private var absent: Set<Node> = []
  private var metrics: [Int: TapeNewlineWordMetric] = [:]

  mutating func configure(words: [TapeNewlineWordMetric], resets: Bool) {
    if resets { absent = [] }
    metrics = Dictionary(uniqueKeysWithValues: words.map { ($0.index, $0) })
    let available = words.flatMap { word -> [Node] in
      let box = Node(kind: .word, index: word.index)
      return word.newlineWidth == nil ? [box] : [box, .init(kind: .beforeNewline, index: word.index),
        .init(kind: .newline, index: word.index), .init(kind: .afterNewline, index: word.index)]
    }
    absent.formIntersection(available)
    nodes = available.filter { !absent.contains($0) }
  }

  mutating func scroll(active: Int, viewportWidth: CGFloat,
    overflowing: (Int) -> Bool, fillerMargin: (Int) -> CGFloat) -> Scroll? {
    guard let activeSlot = nodes.firstIndex(of: .init(kind: .word, index: active)),
      let firstWord = nodes.firstIndex(where: { $0.kind == .word }),
      let gap = metrics[active]?.gap else { return nil }
    let fillers = nodes.indices.filter { nodes[$0].kind == .afterNewline }
    let leading = fillers.filter { $0 < firstWord }
    var correction = leading.last.map { fillerMargin(nodes[$0].index) } ?? 0
    let upcoming = fillers.filter { $0 >= activeSlot }
    let lastSlot = upcoming.prefix(2).last ?? activeSlot - 1
    var advance: CGFloat = 0, before: CGFloat = 0
    var targets: [Int: CGFloat] = [:], adjustments: [Int: CGFloat] = [:]
    var removed: Set<Node> = Set(leading.map { nodes[$0] })
    var removedWords: Set<Int> = []
    if lastSlot >= 0 {
      for slot in 0...lastSlot {
        let node = nodes[slot]
        switch node.kind {
        case .word:
          guard let metric = metrics[node.index] else { continue }
          if overflowing(node.index) {
            removed.insert(node); removedWords.insert(node.index)
            correction += metric.width + metric.gap
          } else {
            advance += metric.width + metric.gap
            if slot < activeSlot { before = advance }
          }
        case .afterNewline:
          guard slot >= firstWord else { continue }
          // A prior horizontal deletion can change this adjacency. Reading
          // the old Return owner's marker unconditionally invents a box.
          let markerOwner = slot >= 3 ? nodes[slot - 3] : nil
          let marker: CGFloat
          if let markerOwner, markerOwner.kind == .word { marker = metrics[markerOwner.index]?.newlineWidth ?? 0 }
          else { marker = 0 }
          advance -= marker + gap
          if slot < activeSlot { before = advance }
          let limit = viewportWidth * 3
          targets[node.index] = min(advance, limit)
          adjustments[node.index] = correction
          if advance >= limit {
            if slot < lastSlot, let next = fillers.first(where: { $0 > slot }) {
              targets[nodes[next].index] = limit
              adjustments[nodes[next].index] = correction
            }
            absent.formUnion(removed); nodes.removeAll { removed.contains($0) }
            return .init(beforeActive: before, indents: targets, fillerCorrections: adjustments,
              compensation: correction, removedWords: removedWords)
          }
        case .beforeNewline, .newline: break
        }
      }
    }
    absent.formUnion(removed); nodes.removeAll { removed.contains($0) }
    return .init(beforeActive: before, indents: targets, fillerCorrections: adjustments,
      compensation: correction, removedWords: removedWords)
  }
}
