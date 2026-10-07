import Foundation

/// A presentation-only snapshot of the entire matched account cache. Never
/// stores prompts, modifies results, or borrows the independently sorted table.
struct AccountHistoryGraphPoint: Identifiable {
  let row: RemoteAccountResult
  let index: Int // newest first; plotted in the opposite direction
  let position: Int
  let speed: Double?
  let accuracy: Double?
  let speed10: Double?
  let speed100: Double?
  let accuracy10: Double?
  let accuracy100: Double?
  let envelope: Double?
  var id: UUID { row.id }
}

struct AccountHistoryGraphs {
  let points: [AccountHistoryGraphPoint]
  let speedChangePerTypingHour: Double?

  struct LinePoint: Identifiable {
    let index: Int
    let position: Int
    let value: Double
    let segment: Int
    var id: Int { index }
  }
  func line(_ key: KeyPath<AccountHistoryGraphPoint, Double?>) -> [LinePoint] {
    var segment = 0
    return points.compactMap { point in
      guard let value = point[keyPath: key] else { segment += 1; return nil }
      return .init(index: point.index, position: point.position, value: value, segment: segment)
    }
  }

  init(_ rows: [RemoteAccountResult]) {
    let ordered = AccountHistoryQuery.sorted(rows)
    let statistics = ordered.map { AccountHistoryStatistics([$0]) }
    let speeds = statistics.map(\.averageWpm), accuracies = statistics.map(\.averageAccuracy)
    let speed10 = Self.averages(speeds, window: 10), speed100 = Self.averages(speeds, window: 100)
    let accuracy10 = Self.averages(accuracies, window: 10), accuracy100 = Self.averages(accuracies, window: 100)
    var envelope = [Double?](repeating: nil, count: rows.count)
    var best: Double?, unknown = false
    for index in ordered.indices.reversed() {
      if let speed = speeds[index] { best = max(best ?? speed, speed) } else { unknown = true }
      envelope[index] = unknown ? nil : best
    }
    points = ordered.indices.map { index in
      .init(row: ordered[index], index: index, position: ordered.count - 1 - index,
        speed: speeds[index], accuracy: accuracies[index], speed10: speed10[index], speed100: speed100[index],
        accuracy10: accuracy10[index], accuracy100: accuracy100[index], envelope: envelope[index])
    }
    if let seconds = AccountHistoryStatistics(ordered).timeTyping, seconds > 0,
      speeds.allSatisfy({ $0 != nil }), let change = Self.fittedChange(speeds.reversed().compactMap { $0 }) {
      speedChangePerTypingHour = change * 3600 / seconds
    } else { speedChangePerTypingHour = nil }
  }

  /// A missing observation invalidates its window, never becomes a zero or
  /// silently shortens it. The old tail is intentionally a partial window.
  static func averages(_ values: [Double?], window: Int) -> [Double?] {
    guard window > 0 else { return values }
    var result = [Double?](repeating: nil, count: values.count)
    var sum = 0.0, missing = 0
    for index in values.indices.reversed() {
      if let value = values[index], value.isFinite { sum += value } else { missing += 1 }
      if index + window < values.count {
        if let value = values[index + window], value.isFinite { sum -= value } else { missing -= 1 }
      }
      if missing == 0 { result[index] = sum / Double(min(window, values.count - index)) }
    }
    return result
  }

  static func fittedChange(_ chronological: [Double]) -> Double? {
    guard chronological.count >= 2, chronological.allSatisfy(\.isFinite) else { return nil }
    let center = Double(chronological.count - 1) / 2
    let average = chronological.reduce(0, +) / Double(chronological.count)
    let terms = chronological.enumerated().map { (Double($0.offset) - center, $0.element - average) }
    let variance = terms.reduce(0) { $0 + $1.0 * $1.0 }
    let covariance = terms.reduce(0) { $0 + $1.0 * $1.1 }
    let change = covariance / variance * Double(chronological.count - 1)
    return change.isFinite ? change : nil
  }

  func nearest(to position: Double) -> AccountHistoryGraphPoint? {
    guard position.isFinite else { return nil }
    return points.min {
      let left = abs(Double($0.position) - position), right = abs(Double($1.position) - position)
      return left == right ? $0.index < $1.index : left < right
    }
  }

  static func visibleLimit(for id: UUID, in table: [RemoteAccountResult], current: Int) -> Int? {
    guard let index = table.firstIndex(where: { $0.id == id }) else { return nil }
    let page = ResultHistoryPagePolicy.pageSize
    let required = ((index / page) + 1) * page
    return min(table.count, max(current, required))
  }
}

/// Native dual axes share a 0...100 ordinate; the left accuracy axis is reversed.
struct AccountHistoryGraphScale {
  let speedLower: Double
  let speedUpper: Double
  let accuracyLower: Double
  let unit: TypingSpeedUnit
  init(points: [AccountHistoryGraphPoint], unit: TypingSpeedUnit, startsAtZero: Bool, speedVisible: Bool) {
    self.unit = unit
    let values = points.compactMap(\.speed).map { unit.converted(wpm: $0) }
    let step: Double
    switch unit { case .wpm: step = 10; case .cpm: step = 100; case .wps: step = 2; case .cps: step = 5; case .wph: step = 1000 }
    speedLower = startsAtZero ? 0 : floor((values.min() ?? 0) / step) * step
    speedUpper = max(speedLower + step, ceil((values.max() ?? 0) / step) * step)
    // Degenerate 100%-only accuracy needs a nonempty native scale.
    accuracyLower = speedVisible ? 0 : min(95, floor((points.compactMap(\.accuracy).min() ?? 0) / 5) * 5)
  }
  func speedPosition(_ wpm: Double) -> Double { (unit.converted(wpm: wpm) - speedLower) / (speedUpper - speedLower) * 100 }
  func accuracyPosition(_ accuracy: Double) -> Double { (100 - accuracy) / (100 - accuracyLower) * 100 }
  func speed(at position: Double) -> Double { speedLower + position / 100 * (speedUpper - speedLower) }
  func accuracy(at position: Double) -> Double { 100 - position / 100 * (100 - accuracyLower) }
}

struct AccountHistoryHistogramBucket: Equatable, Identifiable {
  let lower: Double
  let width: Double
  let count: Int
  var id: Double { lower }
  // Exact source labels, including its fractional-width convention.
  var label: String { "\(SpeedHistogram.formattedBound(lower))-\(SpeedHistogram.formattedBound(lower + width - 1))" }
}

struct AccountHistoryHistogram {
  let buckets: [AccountHistoryHistogramBucket]
  let omittedByReferenceRounding: Int
  let unknownCount: Int
  init(points: [AccountHistoryGraphPoint], unit: TypingSpeedUnit) {
    let speeds = points.compactMap(\.speed).map { unit.converted(wpm: $0) }
    unknownCount = points.count - speeds.count
    guard let maximum = speeds.max() else { buckets = []; omittedByReferenceRounding = 0; return }
    let width = unit.histogramBucketSize, last = Int(floor(maximum / width))
    // Speeds were bounded at 420 WPM before conversion (at most 101 WPH bins).
    let grouped = Dictionary(grouping: speeds, by: { Int(floor(floor($0 + 0.5) / width)) })
    buckets = (0...last).map { .init(lower: Double($0) * width, width: width, count: grouped[$0]?.count ?? 0) }
    omittedByReferenceRounding = speeds.count - buckets.reduce(0) { $0 + $1.count }
  }
}

enum AccountHistoryNumberPresentation {
  static func restartRatio(_ value: Double?) -> String {
    guard let value, value.isFinite, (0...Double(RemoteResultPracticeTiming.maximumRestartCount)).contains(value) else { return "未知" }
    let scaled = value * 10, lower = floor(scaled), fraction = scaled - lower
    // Preserve the binary Number's side of a decimal midpoint. Multiplication
    // alone rounds 1.15 * 10 to 11.5 and would incorrectly print 1.2.
    let residual = (-scaled).addingProduct(value, 10)
    let roundUp = fraction > 0.5 || (fraction == 0.5 && residual >= 0)
    let tenths = Int(lower) + (roundUp ? 1 : 0)
    return "\(tenths / 10).\(tenths % 10)"
  }
  static func text(_ value: Double?, unit: TypingSpeedUnit? = nil, decimals: Bool, forceDecimals: Bool = false) -> String {
    guard let value, value.isFinite else { return "未知" }
    let displayed = unit?.converted(wpm: value) ?? value
    let scaled = decimals || forceDecimals ? (displayed + Double.ulpOfOne) * 100 : displayed
    guard scaled.isFinite else { return "未知" }
    let lower = floor(scaled)
    // Adding 0.5 first would round the nearest value below 0.5 up to 1.
    let integer = scaled - lower < 0.5 ? lower : lower + 1
    let rounded = decimals || forceDecimals ? integer / 100 : integer
    return String(format: decimals || forceDecimals ? "%.2f" : "%.0f", locale: Locale(identifier: "en_US_POSIX"),
      rounded == 0 ? 0.0 : rounded)
  }
}
