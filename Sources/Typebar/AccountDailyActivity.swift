import Foundation

/// Presentation only. The minute and speed ranges are independent so missing
/// practice evidence never hides a known speed or becomes a fabricated zero.
struct AccountDailyActivityScale {
  let minutesUpper: Double
  let speedLower: Double
  let speedUpper: Double
  let unit: TypingSpeedUnit

  init(days: [AccountHistoryDay], unit: TypingSpeedUnit, startsAtZero: Bool) {
    self.unit = unit
    minutesUpper = DailyActivityOverviewScale.niceUpperBound(
      for: days.compactMap(\.statistics.timeTyping).map { $0 / 60 }.max() ?? 0)
    let speeds = days.compactMap(\.statistics.averageWpm).map { unit.converted(wpm: $0) }
    speedLower = startsAtZero ? 0 : DailyActivityOverviewScale.niceLowerBound(for: speeds.min() ?? 0)
    speedUpper = max(DailyActivityOverviewScale.niceUpperBound(for: speeds.max() ?? 0),
      speedLower + max(0.01, abs(speedLower) * 0.1))
  }

  func ordinate(wpm: Double) -> Double {
    (unit.converted(wpm: wpm) - speedLower) / (speedUpper - speedLower) * minutesUpper
  }
  func speed(at ordinate: Double) -> Double {
    speedLower + ordinate / minutesUpper * (speedUpper - speedLower)
  }
  var ticks: [Double] { (0...4).map { Double($0) / 4 * minutesUpper } }
}

struct AccountDailyActivity {
  let days: [AccountHistoryDay]
  let scale: AccountDailyActivityScale
  let trend: [ActivityTypingMinutesTrendPoint]
  struct SpeedPoint: Identifiable {
    let day: Date
    let wpm: Double
    let segment: Int
    var id: Date { day }
  }
  let speeds: [SpeedPoint]

  init(days: [AccountHistoryDay], unit: TypingSpeedUnit, startsAtZero: Bool) {
    let ordered = days.filter { $0.statistics.completed > 0 && $0.day.timeIntervalSinceReferenceDate.isFinite }
      .sorted { $0.day < $1.day }
    self.days = ordered
    scale = .init(days: ordered, unit: unit, startsAtZero: startsAtZero)
    let known = ordered.compactMap { day -> ActivityBarPoint? in
      guard let seconds = day.statistics.timeTyping else { return nil }
      return .init(day: day.day, completedTests: day.statistics.completed, typingSeconds: seconds)
    }
    trend = ActivityTypingMinutesTrendPolicy.clipped(ActivityTypingMinutesTrendPolicy.fitted(for: known), upper: scale.minutesUpper)
    var segment = 0
    speeds = ordered.compactMap { day in
      guard let wpm = day.statistics.averageWpm else { segment += 1; return nil }
      return .init(day: day.day, wpm: wpm, segment: segment)
    }
  }

  var unknownMinuteDays: Int { days.filter { $0.statistics.timeTyping == nil }.count }
  /// A viewport, not synthetic observations. Keep unknown-only dates selectable
  /// even when no bar or speed mark can contribute an inferred chart domain.
  var dateDomain: ClosedRange<Date> {
    guard let first = days.first?.day, let last = days.last?.day else {
      return Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 86400)
    }
    return first == last ? first.addingTimeInterval(-43200)...last.addingTimeInterval(43200) : first...last
  }
  func nearest(to date: Date) -> AccountHistoryDay? {
    guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
    return days.min {
      let left = abs($0.day.timeIntervalSince(date)), right = abs($1.day.timeIntervalSince(date))
      return left == right ? $0.day < $1.day : left < right
    }
  }
}
