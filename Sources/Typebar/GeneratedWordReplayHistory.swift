/// Actual sampled source/target pairs. Unlike chunk replay, this survives a
/// configuration change that shortens the opening or selects another pool.
/// Value-owned and process-local; never a website field or persisted record.
struct GeneratedWordReplayHistory {
  struct Word { let source, target: String }
  let noSpace: Bool
  private var words: [Word] = []
  init(noSpace: Bool) { self.noSpace = noSpace }
  var count: Int { words.count }
  func word(at index: Int) -> Word? { words.indices.contains(index) ? words[index] : nil }
  mutating func append(source: String, target: String) { words.append(.init(source: source, target: target)) }
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
