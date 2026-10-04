import Foundation

enum WeeklyExperiencePresentation {
  /// The source XP table rounds seconds and always shows hours and minutes.
  static func duration(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, (0...9_007_199_254_740_991).contains(seconds) else { return "—" }
    let whole = Int(seconds.rounded(.toNearestOrAwayFromZero))
    return [whole / 3_600, whole % 3_600 / 60, whole % 60]
      .map { $0 < 10 ? "0\($0)" : "\($0)" }.joined(separator:":")
  }
  static func activityDate(_ timestamp: Int?) -> Date? {
    guard let timestamp, abs(Double(timestamp)) <= 8_640_000_000_000_000 else { return nil }
    return Date(timeIntervalSince1970:Double(timestamp) / 1_000)
  }
  static func activityLabel(_ timestamp: Int?) -> String {
    guard let date = activityDate(timestamp) else { return "活动时间未知" }
    return "活动 \(date.formatted(date:.abbreviated,time:.shortened))"
  }
}
