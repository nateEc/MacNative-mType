import Foundation

/// Speed input units are deliberately separate from native cursor/diagnostic
/// characters. A word can earn credit only as a whole, or as the active prefix.
struct TypingWordCredit {
  var characters = 0
  var inputUnits = 0

  static func word(target: String, input: String, creditsPrefix: Bool) -> Self {
    let targetUnits = Array(target.utf16)
    let inputUnits = Array(input.utf16)
    guard targetUnits == inputUnits || (creditsPrefix && targetUnits.starts(with: inputUnits))
    else { return .init() }
    return .init(characters: input.count, inputUnits: inputUnits.count)
  }

  static func words(target: String, input: String, creditsActivePrefix: Bool,
    retainedSeparatorIndices: Set<Int> = []) -> Self {
    let targets = wordsWithCommits(target)
    let inputs = wordsWithCommits(input, retainedSeparatorIndices: retainedSeparatorIndices)
    return inputs.enumerated().reduce(into: Self()) { total, entry in
      let (index, text) = entry
      let credit: Self
      if targets.indices.contains(index) {
        credit = word(target: targets[index], input: text,
          creditsPrefix: creditsActivePrefix && index == inputs.count - 1
            && (text.last.map(isPromptWordSeparator) != true
              || retainedSeparatorIndices.contains(input.count - 1)))
      } else {
        // No retained target means self-entered content, not invented errors.
        credit = .init(characters: text.count, inputUnits: text.utf16.count)
      }
      total.characters += credit.characters
      total.inputUnits += credit.inputUnits
    }
  }

  private static func wordsWithCommits(_ text: String,
    retainedSeparatorIndices: Set<Int> = []) -> [String] {
    var words: [String] = []
    var current = ""
    for (index, character) in text.enumerated() {
      current.append(character)
      if isPromptWordSeparator(character), !retainedSeparatorIndices.contains(index) {
        words.append(current)
        current = ""
      }
    }
    if !current.isEmpty { words.append(current) }
    return words
  }
}
