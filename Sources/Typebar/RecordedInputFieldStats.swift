import Foundation

/// Source-time snapshots for known input fields and target-free Zen fields.
/// Navigation's accepted buffer and saved history are different readers.
struct RecordedInputFieldStats {
  private struct Snapshot {
    let units: [UInt16]
    let classifiedUnits: [UInt16]
    let offset: TimeInterval
    let insertedSpace: Bool
  }
  private var order: [Int] = []
  private var snapshots: [Int: Snapshot] = [:]
  private var firstOffsets: [Int: TimeInterval] = [:]
  private var clearOffsets: [Int: TimeInterval] = [:]

  mutating func record(_ event: TypingReplayEvent) {
    guard let field = event.inputField, field.index >= 0, event.offset.isFinite else { return }
    var needsSort = false
    if firstOffsets[field.index] == nil {
      needsSort = order.last.map { firstOffsets[$0]! > event.offset } ?? false
      order.append(field.index); firstOffsets[field.index] = event.offset
    } else if event.offset < firstOffsets[field.index]! {
      firstOffsets[field.index] = event.offset
      needsSort = true
    }
    // Stable sort preserves first arrival for equal source times.
    if needsSort { order = order.enumerated().sorted {
      let lhs = firstOffsets[$0.element]!, rhs = firstOffsets[$1.element]!
      return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
    }.map(\.element) }
    if event.offset >= snapshots[field.index]?.offset ?? -Double.infinity {
      snapshots[field.index] = .init(units: field.units, classifiedUnits: Self.classificationInput(for: event), offset: event.offset,
        insertedSpace: event.kind == .insert && event.inputUnits == [32])
    }
    if event.validatedClearedNextWord {
      let next = field.index + 1
      clearOffsets[next] = max(clearOffsets[next] ?? -Double.infinity, event.offset)
    }
  }

  /// Source getInputFromDom trims only an incorrect final SPACE commit.
  /// Terminal and interval readers share this rule, never the saved buffer.
  static func classificationInput(for event: TypingReplayEvent) -> [UInt16] {
    var units = event.inputField?.units ?? []
    if event.kind == .insert, event.inputUnits == [32], !event.isStoppedInsertion,
      event.commitsWord != false, event.inputPosition?.lastWord == true,
      event.inputCorrectness?.last == false {
      while let unit = units.last, let scalar = UnicodeScalar(UInt32(unit)),
        QuoteSourcePolicy.isBoundaryWhitespace(scalar) { units.removeLast() }
    }
    return units
  }

  func history(_ index: Int) -> [UInt16] {
    guard let snapshot = snapshots[index] else { return [] }
    return (clearOffsets[index] ?? -Double.infinity) > snapshot.offset ? [] : snapshot.units
  }

  func counts(targets: UnitInputTargets, creditsActivePrefix: Bool, basis: ResultScoringUnitBasis = .utf16)
    -> (credit: TypingWordCredit, rawUnits: Int, rawCharacters: Int,
      unitStats: ResultUnitCharacterStats, retainedInputUnits: Int) {
    let highest = snapshots.filter { !$0.value.classifiedUnits.isEmpty }.keys.max() ?? 0
    let active = snapshots[highest]?.insertedSpace == true && highest < Int.max ? highest + 1 : highest
    var credit = TypingWordCredit(); var raw: [UInt16] = []
    var unitStats = ResultUnitCharacterStats()
    for index in order {
      let input = snapshots[index]!.classifiedUnits
      let target = targets.fields.indices.contains(index) ? targets.field(index) : nil
      let stats = ResultUnitCharacterStats.classify(input: input, target: target,
        creditsPartial: index == active && creditsActivePrefix, basis: basis)
      unitStats.add(stats)
      if stats.correctWord > 0 {
        credit.inputUnits += stats.correctWord
        // A syllable may become a correct jamo prefix without being a
        // matching native glyph (가 versus 각). Do not change that old reader.
        let creditsRawGlyphs = basis != .koreanJamo || (target.map {
          input == $0 || index == active && creditsActivePrefix && $0.starts(with: input)
        } ?? true)
        if creditsRawGlyphs {
          credit.characters += String(decoding: input, as: UTF16.self).count
        }
      }
      raw += input
      if index == active { break }
    }
    // Positional classification conserves projected entered units. Keep the
    // pre-projection count and native glyph reader independent of that sum.
    return (credit, unitStats.allCorrect + unitStats.incorrect + unitStats.extra,
      String(decoding: raw, as: UTF16.self).count, unitStats, raw.count)
  }
}
