import Foundation

/// A single active word's uncommitted tail. Target identities and caret
/// ownership are independent of candidate ink; no input or score is changed.
/// Native offsets count extended graphemes, like the session's prompt IDs.
struct PromptCompositionPlan {
  struct Cell: Equatable {
    let text: String
    let targetIndex: Int?
    let compositionIndex: Int?
    let matchesTarget: Bool
  }

  enum Caret: Equatable {
    case target(Int)
    case afterComposition(Int)
    case afterInput
  }

  let cells: [Cell]
  let replacedTargetRange: Range<Int>
  let caret: Caret
  let hasEmptyPlaceholder: Bool
  let wordLetterIndex: Int
  /// Keep the source coordinate available without treating a surrogate cell
  /// or part of a combining sequence as a native target glyph identity.
  let referenceLetterUnitIndex: Int

  init(target: String, input: String, composition: String, isZen: Bool, style: CompositionDisplayStyle) {
    let target = isZen ? [] : Array(target)
    let marked = Array(composition), start = input.count
    wordLetterIndex = start + marked.count
    referenceLetterUnitIndex = input.utf16.count + composition.utf16.count
    let lower = min(start, target.count)
    let upper = lower + min(marked.count, target.count - lower)
    replacedTargetRange = lower..<upper
    hasEmptyPlaceholder = isZen && input.isEmpty && marked.isEmpty
    var output = [Cell]()
    for (index, character) in marked.enumerated() {
      let targetIndex = start + index
      let original = target.indices.contains(targetIndex) ? target[targetIndex] : nil
      let text = isZen ? String(character) : style == .replace
        ? (character == " " ? "_" : String(character)) : String(original ?? character)
      output.append(.init(text: text, targetIndex: original == nil ? nil : targetIndex,
        compositionIndex: index, matchesTarget: original.map { InputTextIdentity.matches($0, character) } ?? false))
    }
    for index in upper..<target.count {
      output.append(.init(text: String(target[index]), targetIndex: index,
        compositionIndex: nil, matchesTarget: false))
    }
    cells = output
    if upper < target.count { caret = .target(upper) }
    else if !marked.isEmpty { caret = .afterComposition(marked.count - 1) }
    else { caret = .afterInput }
  }
}
