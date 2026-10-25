import Foundation
import Observation

/// Source logical-key registry. Physical keycap completion clears all its aliases;
/// an unmatched logical key has no animation and therefore no expiry timer.
struct WebsiteKeymapFlashState {
  struct Entry: Equatable {
    let tick: Int
    let isCorrect: Bool
  }
  struct Selection: Equatable {
    let units: [UInt16]
    let tick: Int
    let isCorrect: Bool
    let identity: UInt64
  }
  private(set) var entries: [[UInt16]: Entry] = [:]
  private var identities: [[UInt16]: UInt64] = [:]
  private var nextIdentity: UInt64 = 0

  mutating func receive(_ events: [WebsiteKeymapInputEvent]) {
    for event in events {
      let key = event.units.isEmpty ? [UInt16(32)] : event.units
      nextIdentity &+= 1
      identities[key] = nextIdentity
      entries[key] = .init(tick: (entries[key]?.tick ?? 0) + 1,
        isCorrect: event.isCorrect)
    }
  }

  func first(for legends: [[UInt16]]) -> Selection? {
    for legend in legends {
      if let entry = entries[legend] {
        return .init(units: legend, tick: entry.tick, isCorrect: entry.isCorrect, identity: identities[legend] ?? 0)
      }
    }
    return nil
  }

  mutating func complete(legends: [[UInt16]]) {
    for legend in legends { entries.removeValue(forKey: legend); identities.removeValue(forKey: legend) }
  }
}

/// A window owner records events synchronously, before SwiftUI can coalesce
/// multiple input callbacks. Retired keycaps cannot complete a new attempt.
@MainActor @Observable
final class WebsiteKeymapFeedbackStore {
  private(set) var state = WebsiteKeymapFlashState()
  private(set) var generation: UInt64 = 0

  func receive(_ events: [WebsiteKeymapInputEvent]) {
    guard !events.isEmpty else { return }
    state.receive(events)
  }

  func complete(legends: [[UInt16]], generation expected: UInt64, selection: WebsiteKeymapFlashState.Selection?) {
    guard generation == expected, state.first(for: legends) == selection,
      legends.contains(where: { state.entries[$0] != nil }) else { return }
    state.complete(legends: legends)
  }

  func reset() {
    generation &+= 1
    state = .init()
  }
}
