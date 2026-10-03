import Foundation

/// Source-time snapshots for live known no-space and target-free Zen fields.
/// Navigation's accepted buffer and saved history are different readers.
struct RecordedInputFieldStats {
  private struct Snapshot {
    let units: [UInt16]
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
      snapshots[field.index] = .init(units: field.units, offset: event.offset,
        insertedSpace: event.kind == .insert && event.inputUnits == [32])
    }
    if event.validatedClearedNextWord {
      let next = field.index + 1
      clearOffsets[next] = max(clearOffsets[next] ?? -Double.infinity, event.offset)
    }
  }

  func history(_ index: Int) -> [UInt16] {
    guard let snapshot = snapshots[index] else { return [] }
    return (clearOffsets[index] ?? -Double.infinity) > snapshot.offset ? [] : snapshot.units
  }

  func counts(targets: UnitInputTargets, creditsActivePrefix: Bool)
    -> (credit: TypingWordCredit, rawUnits: Int, rawCharacters: Int, unitStats: ResultUnitCharacterStats) {
    let highest = snapshots.filter { !$0.value.units.isEmpty }.keys.max() ?? 0
    let active = snapshots[highest]?.insertedSpace == true && highest < Int.max ? highest + 1 : highest
    var credit = TypingWordCredit(); var raw: [UInt16] = []
    var unitStats = ResultUnitCharacterStats()
    for index in order {
      let input = snapshots[index]!.units
      let target = targets.fields.indices.contains(index) ? targets.field(index) : nil
      let stats = ResultUnitCharacterStats.classify(input: input, target: target,
        creditsPartial: index == active && creditsActivePrefix)
      unitStats.add(stats)
      if stats.correctWord > 0 {
        credit.inputUnits += stats.correctWord
        credit.characters += String(decoding: input, as: UTF16.self).count
      }
      raw += input
      if index == active { break }
    }
    return (credit, raw.count, String(decoding: raw, as: UTF16.self).count, unitStats)
  }
}
