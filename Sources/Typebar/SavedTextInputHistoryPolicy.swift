import Foundation

/// An end-of-attempt projection of accepted native input. Kept separate from
/// navigation and scoring: a deleted future field remains in history, and
/// only the final field is tested for sufficient UTF-16 display length.
enum SavedTextInputHistoryPolicy {
  private struct Piece {
    let field: Int
    let text: String
  }

  static func displayWords(in prompt: String) -> [String] {
    var words: [String] = []
    var word = ""
    for character in prompt {
      if character == " " {
        words.append(word)
        word = ""
      } else if character == "\n" {
        words.append(word + "\n")
        word = ""
      } else {
        word.append(character)
      }
    }
    if !word.isEmpty { words.append(word) }
    return words
  }

  static func progressWordCount(
    displays: [String], events: [TypingReplayEvent], noSpaceWordEnds: [Int] = []
  ) -> Int {
    guard !displays.isEmpty else { return 0 }
    var fields: [String] = []
    var pieces: [Piece] = []
    var live = ""
    var liveGraphemeCount = 0
    var field = 0
    var trimsLastField = false
    let noSpaceFieldLimit = noSpaceWordEnds.isEmpty ? displays.count
      : displays.firstIndex(of: "") ?? noSpaceWordEnds.count
    for event in events {
      trimsLastField = false
      switch event.kind {
      case .insert:
        for character in event.text {
          if !noSpaceWordEnds.isEmpty {
            // Native no-space target boundaries are grapheme offsets. A
            // binary search avoids rescanning every target for every event.
            var lower = 0
            var upper = noSpaceFieldLimit
            while lower < upper {
              let middle = (lower + upper) / 2
              if noSpaceWordEnds[middle] <= liveGraphemeCount { lower = middle + 1 }
              else { upper = middle }
            }
            field = min(lower, displays.count - 1)
          }
          while fields.count <= field { fields.append("") }
          let text = String(character)
          trimsLastField = noSpaceWordEnds.isEmpty && character == " "
            && event.commitsWord != false && field == displays.count - 1
            && (fields[field] != displays[field] || event.forceError)
          fields[field].append(character)
          pieces.append(.init(field: field, text: text))
          // Separate input events can fuse into one native grapheme (e + a
          // combining mark). Deletion still removes that entire grapheme.
          liveGraphemeCount += live.last.map { String([$0, character]).count - 1 } ?? 1
          live.append(character)
          if noSpaceWordEnds.isEmpty && isPromptWordSeparator(character)
            && event.commitsWord != false { field += 1 }
        }
      case .delete:
        guard let last = live.last else { continue }
        var unitsToRemove = last.utf16.count
        live.removeLast()
        liveGraphemeCount -= 1
        while unitsToRemove > 0, let piece = pieces.popLast() {
          // Regional indicators can regroup across insert events. A single
          // native backspace may remove only a suffix of an earlier piece.
          var remainder = piece.text
          var removedScalars = 0
          while unitsToRemove > 0, let scalar = remainder.unicodeScalars.popLast() {
            unitsToRemove -= scalar.utf16.count
            removedScalars += 1
          }
          fields[piece.field].unicodeScalars.removeLast(removedScalars)
          if !remainder.isEmpty { pieces.append(.init(field: piece.field, text: remainder)) }
          field = piece.field
        }
      }
    }
    guard var last = fields.last else { return 0 }
    if trimsLastField {
      while let scalar = last.unicodeScalars.last, QuoteSourcePolicy.isBoundaryWhitespace(scalar) {
        last.unicodeScalars.removeLast()
      }
    }
    let targetLength = fields.count <= displays.count ? displays[fields.count - 1].utf16.count : 0
    return fields.count - (last.utf16.count < targetLength ? 1 : 0)
  }
}
