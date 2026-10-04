import Foundation

/// Captured timer/physical-clock evidence, independent of real date stamps and
/// accepted text. Absence remains absence for legacy or unobserved attempts.
struct ResultTerminalTiming: Codable, Equatable, Sendable {
  let version: Int
  let endMilliseconds: Double
  let lastKeypressMilliseconds: Double?

  var boundaryDuration: TimeInterval {
    let gap = lastKeypressMilliseconds.map { Self.round(endMilliseconds - $0) }
    return max(0, endMilliseconds - (gap.map { $0 < 7_000 ? max(0, $0) : 0 } ?? 0)) / 1_000
  }

  func duration(mode: TestMode) -> TimeInterval {
    mode == .custom ? boundaryDuration : Self.round(boundaryDuration)
  }

  func isValid(wallClockDuration: TimeInterval, mode: TestMode, outcome: TestOutcome,
    wallClockToleranceMilliseconds: Double = 0.011) -> Bool {
    guard version == 1, mode == .zen || outcome == .bailedOut,
      outcome != .active, outcome != .abandoned,
      endMilliseconds.isFinite, endMilliseconds >= 0, wallClockDuration.isFinite,
      abs(endMilliseconds - wallClockDuration * 1_000) <= wallClockToleranceMilliseconds
    else { return false }
    if let lastKeypressMilliseconds {
      guard lastKeypressMilliseconds.isFinite, lastKeypressMilliseconds <= endMilliseconds,
        (endMilliseconds - lastKeypressMilliseconds).isFinite else { return false }
    }
    return true
  }

  static func round(_ value: Double) -> Double {
    guard value.isFinite, abs(value) <= Double.greatestFiniteMagnitude / 100 else { return value }
    return ((value + Double.ulpOfOne) * 100).rounded() / 100
  }

  static func includesFractionalTail(_ configuration: TestConfiguration) -> Bool {
    switch configuration.mode {
    case .time: false
    case .words: configuration.wordLimit != 0
    case .quote, .zen: true
    case .custom:
      configuration.customTextCompletion != .time && !configuration.isInfinite
    }
  }
}

/// Track only source-equivalent physical downs for terminal duration and AFK.
/// Existing native hold/overlap tracking is deliberately left untouched.
struct TerminalPhysicalActivity {
  private(set) var wasObserved = false
  private var downs: [Date] = []
  private var lastEvent: Date?

  mutating func record(code: UInt16, down: Bool, isRepeat: Bool, at date: Date,
    modifiers: [TestModifier]) {
    guard date.timeIntervalSinceReferenceDate.isFinite, lastEvent.map({ date >= $0 }) ?? true else { return }
    wasObserved = true
    lastEvent = date
    guard down, !isRepeat, Self.tracks(code, modifiers: modifiers) else { return }
    downs.append(date)
  }

  static func tracks(_ code: UInt16, modifiers: [TestModifier]) -> Bool {
    if (0...50).contains(code) { return true } // ANSI/ISO letters, numbers, Tab, Return, space.
    if [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92].contains(code) { return true }
    if (123...126).contains(code) { return modifiers.contains(.arrowStream) }
    return code == 76 && modifiers.contains(.accountingStream)
  }

  func offsets(startedAt: Date, finishedAt: Date) -> [Double] {
    let before = downs.lastIndex { $0 < startedAt }
    return downs.enumerated().compactMap { index, date in
      guard date <= finishedAt, date >= startedAt || index == before else { return nil }
      return ResultTerminalTiming.round(date.timeIntervalSince(startedAt) * 1_000)
    }
  }

  func snapshot(startedAt: Date, finishedAt: Date) -> ResultTerminalTiming? {
    guard wasObserved else { return nil }
    let end = ResultTerminalTiming.round(max(0, finishedAt.timeIntervalSince(startedAt)) * 1_000)
    return .init(version: 1, endMilliseconds: end,
      lastKeypressMilliseconds: offsets(startedAt: startedAt, finishedAt: finishedAt).last)
  }
}

enum TerminalInactivity {
  static func counts(offsets: [Double], timing: ResultTerminalTiming,
    configuration: TestConfiguration) -> [Int] {
    let boundaries = TestInactivityPolicy.intervalBoundaries(duration: timing.boundaryDuration,
      includesFractionalTail: ResultTerminalTiming.includesFractionalTail(configuration))
    var counts = Array(repeating: 0, count: boundaries.count)
    for milliseconds in offsets {
      var low = 0, high = boundaries.count
      while low < high {
        let middle = low + (high - low) / 2
        if boundaries[middle] * 1_000 < milliseconds { low = middle + 1 } else { high = middle }
      }
      if low < counts.count { counts[low] += 1 }
    }
    return counts
  }
}
