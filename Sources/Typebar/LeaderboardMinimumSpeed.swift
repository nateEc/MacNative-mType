import Foundation

enum LeaderboardMinimumSpeedPresentation {
  /// A read-time tail, not a configured admission threshold or a guarantee
  /// that matching the speed wins an accuracy/time tie.
  static func message(minWpm: Double?, period: RemoteLeaderboardPeriod,
    scope: RemoteLeaderboardScope, unit: TypingSpeedUnit) -> String? {
    guard period == .day || period == .yesterday, let minWpm,
      minWpm.isFinite, minWpm >= 0 else { return nil }
    let speed = unit.converted(wpm: minWpm)
    guard speed.isFinite else { return nil }
    let population = scope == .friends ? "好友榜" : "榜单"
    return "当前\(population)榜尾速度 \(String(format: "%.2f", speed)) \(unit.displayName)（入榜参考）"
  }
}
