/// Actual sampled source/target pairs. Unlike chunk replay, this survives a
/// configuration change that shortens the opening or selects another pool.
/// Value-owned and process-local; never a website field or persisted record.
struct GeneratedWordReplayHistory {
  struct Word {
    let source, target, committedText: String
    let sectionIndex: Int
  }
  let noSpace: Bool
  var arrowChart: WebsiteArrowChart
  private var words: [Word] = []
  private(set) var preservesCommitFraming = false
  init(noSpace: Bool, arrowChart: WebsiteArrowChart = .init()) { self.noSpace = noSpace; self.arrowChart = arrowChart }
  var count: Int { words.count }
  func word(at index: Int) -> Word? { words.indices.contains(index) ? words[index] : nil }
  mutating func preserveCommitFraming() { preservesCommitFraming = true }
  mutating func append(source: String, target: String, committedText: String? = nil, sectionIndex: Int? = nil) {
    words.append(.init(source: source, target: target,
      committedText: committedText ?? target + (!noSpace && !target.hasSuffix("\n") ? " " : ""),
      sectionIndex: sectionIndex ?? (words.count + 1)))
  }
}

/// Permission after a repeated history miss, not ordinary fresh generation.
/// In particular the source does not special-case words=0 as infinite here.
enum GeneratedRepeatedWordPolicy {
  static func permitsFreshWord(configuration: TestConfiguration, wordIndex: Int, sectionIndex: Int) -> Bool {
    switch configuration.mode {
    case .time: true
    case .words: wordIndex < (configuration.wordLimit ?? 0)
    case .custom:
      switch configuration.customTextCompletion {
      case .time: true
      case .words: wordIndex < (configuration.wordLimit ?? 0)
      case .sections: sectionIndex < (configuration.customTextSectionLimit ?? 0)
      case .finish: false
      }
    case .quote, .zen: false
    }
  }
}
