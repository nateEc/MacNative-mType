import Foundation

/// An end-of-attempt projection of accepted native input. Kept separate from
/// navigation and scoring: a future bucket remains, but an explicit later
/// abandonment can empty its saved value without changing its scoring snapshot;
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
    let history = projectInput(displays: displays, events: events, noSpaceWordEnds: noSpaceWordEnds)
    guard var last = history.fields.last else { return 0 }
    if history.trimsLastField {
      while let scalar = last.unicodeScalars.last, QuoteSourcePolicy.isBoundaryWhitespace(scalar) {
        last.unicodeScalars.removeLast()
      }
    }
    let targetLength = history.fields.count <= displays.count ? displays[history.fields.count - 1].utf16.count : 0
    return history.fields.count - (last.utf16.count < targetLength ? 1 : 0)
  }

  /// Final accepted fields, including their commits. Playback submission
  /// cues use this history, not a transient spelling or a progress count.
  static func inputFields(events: [TypingReplayEvent]) -> [String] {
    projectInput(displays: [], events: events, noSpaceWordEnds: []).fields
  }

  /// Display text is not input identity for lone surrogates. Raw fields stay
  /// in source-time order, including a deleted future field's empty snapshot.
  /// Missing legacy metadata is never inferred from replacement characters.
  static func inputFieldUTF16(events: [TypingReplayEvent]) -> [[UInt16]] {
    guard !events.isEmpty, events.allSatisfy({ $0.inputField != nil }) else {
      if hasValidatedRawUnits(events) { return rawPrimitiveFields(displays: [], events: events).fields }
      return inputFields(events: events).map { Array($0.utf16) }
    }
    var order: [Int] = []
    var fields: [Int: [UInt16]] = [:]
    var offsets: [Int: TimeInterval] = [:]
    var clearOffsets: [Int: TimeInterval] = [:]
    for event in TypingReplay.chronologicalEvents(events) {
      guard let field = event.inputField, field.index >= 0 else { continue }
      if fields[field.index] == nil { order.append(field.index) }
      fields[field.index] = field.units
      offsets[field.index] = event.offset
      if event.validatedClearedNextWord {
        let next = field.index + 1
        clearOffsets[next] = max(clearOffsets[next] ?? -Double.infinity, event.offset)
      }
    }
    return order.map { index in
      (clearOffsets[index] ?? -Double.infinity) > (offsets[index] ?? -Double.infinity) ? [] : fields[index] ?? []
    }
  }

  private static func projectInput(
    displays: [String], events: [TypingReplayEvent], noSpaceWordEnds: [Int]
  ) -> (fields: [String], trimsLastField: Bool) {
    if !events.isEmpty, events.allSatisfy({ $0.inputField != nil }) {
      return recordedFields(displays: displays, events: events)
    }
    if noSpaceWordEnds.isEmpty, hasValidatedRawUnits(events) {
      let raw = rawPrimitiveFields(displays: displays, events: events)
      return (raw.fields.map { String(decoding: $0, as: UTF16.self) }, raw.trimsLastField)
    }
    var fields: [String] = []
    var pieces: [Piece] = []
    var live = ""
    var liveGraphemeCount = 0
    var field = 0
    var trimsLastField = false
    let noSpaceFieldLimit = noSpaceWordEnds.isEmpty ? displays.count
      : displays.firstIndex(of: "") ?? noSpaceWordEnds.count
    for event in events {
      if event.isStoppedInsertion {
        while fields.count <= field { fields.append("") }
        continue
      }
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
    return (fields, trimsLastField)
  }

  private static func hasValidatedRawUnits(_ events: [TypingReplayEvent]) -> Bool {
    events.contains { $0.validatedTextUTF16 != nil || $0.inputField?.validatedValueUTF16 != nil }
  }

  /// No snapshots or hidden target segmentation: own primitive buckets are
  /// still lossless. A deletion can leave a lone surrogate or combining base.
  /// Old primitives remove a whole grapheme; marked new primitives remove a unit.
  private static func rawPrimitiveFields(
    displays: [String], events: [TypingReplayEvent]
  ) -> (fields: [[UInt16]], trimsLastField: Bool) {
    var fields: [[UInt16]] = []
    var pieces: [(field: Int, unit: UInt16)] = []
    var live: [UInt16] = []
    var field = 0
    var trimsLastField = false
    for event in TypingReplay.chronologicalEvents(events) {
      if event.isStoppedInsertion {
        while fields.count <= field { fields.append([]) }
        continue
      }
      trimsLastField = false
      switch event.kind {
      case .insert:
        for unit in event.inputUnits {
          while fields.count <= field { fields.append([]) }
          trimsLastField = unit == 32 && event.commitsWord != false && field == displays.count - 1
            && (fields[field] != Array(displays[field].utf16) || event.forceError)
          fields[field].append(unit)
          pieces.append((field, unit))
          live.append(unit)
          if (unit == 32 || unit == 10) && event.commitsWord != false { field += 1 }
        }
      case .delete:
        guard !live.isEmpty else { continue }
        let count = event.deletesUTF16Unit ? 1
          : String(decoding: live, as: UTF16.self).last.map { String($0).utf16.count } ?? 0
        let removed = min(count, live.count)
        live.removeLast(removed)
        for _ in 0..<removed {
          guard let piece = pieces.popLast() else { break }
          fields[piece.field].removeLast()
          field = piece.field
        }
      }
    }
    return (fields, trimsLastField)
  }

  /// Keep source time sorting and the last recorded snapshot in each bucket.
  /// Do not apply a delayed field-local deletion to the whole accepted text.
  private static func recordedFields(
    displays: [String], events: [TypingReplayEvent]
  ) -> (fields: [String], trimsLastField: Bool) {
    var trimsLastField = false
    for event in TypingReplay.chronologicalEvents(events) {
      guard let snapshot = event.inputField, snapshot.index >= 0 else { continue }
      trimsLastField = !event.isStoppedInsertion && event.kind == .insert
        && event.text == " " && event.commitsWord != false
        && snapshot.index == displays.count - 1
        && (String(snapshot.value.dropLast()) != displays[snapshot.index] || event.forceError)
    }
    return (inputFieldUTF16(events: events).map { String(decoding: $0, as: UTF16.self) }, trimsLastField)
  }
}
