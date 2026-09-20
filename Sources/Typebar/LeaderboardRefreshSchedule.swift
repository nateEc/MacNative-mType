import Foundation

/// The reference leaderboard exposes when a view will refresh or reset. This
/// native version keeps that indicator entirely local: it derives the same
/// UTC cadence from the selected period and never starts a network request.
enum LeaderboardRefreshSchedule {
  private static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  static func remainingSeconds(for period: RemoteLeaderboardPeriod, at date: Date) -> Int? {
    switch period {
    case .all: allTimeRefreshRemainingSeconds(at: date)
    case .day: resetRemainingSeconds(at: date, boundary: .day)
    case .yesterday: nil
    case .week: resetRemainingSeconds(at: date, boundary: .week)
    }
  }

  static func remainingSeconds(
    for period: RemoteExperienceLeaderboardPeriod, at date: Date
  ) -> Int? {
    period == .week ? resetRemainingSeconds(at: date, boundary: .week) : nil
  }

  static func message(for period: RemoteLeaderboardPeriod, at date: Date) -> String? {
    guard let seconds = remainingSeconds(for: period, at: date) else { return nil }
    let label = period == .all ? "下次刷新" : "下次重置"
    return "\(label)：\(formatted(seconds))"
  }

  static func message(for period: RemoteExperienceLeaderboardPeriod, at date: Date) -> String? {
    guard let seconds = remainingSeconds(for: period, at: date) else { return nil }
    return "下次重置：\(formatted(seconds))"
  }

  private enum Boundary {
    case day
    case week
  }

  private static func allTimeRefreshRemainingSeconds(at date: Date) -> Int {
    let interval: TimeInterval = 15 * 60
    let nextBoundary = (date.timeIntervalSince1970 / interval).rounded(.down) * interval + interval
    return max(1, Int((nextBoundary - date.timeIntervalSince1970).rounded(.down)))
  }

  private static func resetRemainingSeconds(at date: Date, boundary: Boundary) -> Int {
    let calendar = utcCalendar
    let startOfToday = calendar.startOfDay(for: date)
    let nextBoundary: Date
    switch boundary {
    case .day:
      nextBoundary = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
    case .week:
      let weekday = calendar.component(.weekday, from: date)
      let daysUntilMonday = (9 - weekday) % 7
      let daysToAdd = daysUntilMonday == 0 ? 7 : daysUntilMonday
      nextBoundary = calendar.date(byAdding: .day, value: daysToAdd, to: startOfToday)!
    }
    // The reference calculates against the final millisecond of the active
    // UTC day/week, so midnight displays 23:59:59 rather than 24:00:00.
    return max(0, Int((nextBoundary.timeIntervalSince(date) - 0.001).rounded(.down)))
  }

  private static func formatted(_ seconds: Int) -> String {
    let days = seconds / 86_400
    let hours = seconds % 86_400 / 3_600
    let minutes = seconds % 3_600 / 60
    let remainingSeconds = seconds % 60
    if days > 0 {
      let clock = String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
      return "\(days) 天 \(clock)"
    }
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%02d:%02d", minutes, remainingSeconds)
  }
}
