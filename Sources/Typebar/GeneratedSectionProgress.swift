import Foundation

/// The visible counter belongs to the current stored word, independently of
/// the generator's section quota and the number of committed input fields.
struct GeneratedSectionProgress {
  let completed: Int
  let total: Double
  let activeWord: Int

  init(history: GeneratedWordReplayHistory, publishedWords: Int, activeWord: Int, total: Double) {
    self.activeWord = activeWord
    self.total = total
    if activeWord >= 0, activeWord < publishedWords, let word = history.word(at: activeWord) {
      completed = word.sectionIndex - 1
    } else { completed = 0 }
  }

  var text: String {
    total == 0 ? String(activeWord) : "\(completed)/\(WebsiteNumberText.decimal(total))"
  }

  func bar(hasElapsed: Bool, calculating: Bool, bailedOut: Bool) -> (fraction: Double, duration: TimeInterval) {
    guard hasElapsed, total != 0 else { return (0, 0) }
    if calculating && !bailedOut { return (1, 0.125) }
    return (floor(Double(completed) / total * 100) / 100, 0.25)
  }
}
