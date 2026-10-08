import Foundation

struct FriendComparisonRow: Identifiable {
  let profile: RemotePublicProfile
  let connectedAt: Date?
  let isOwner: Bool
  private let top15: RemotePublicProfileBest?
  private let top60: RemotePublicProfileBest?
  init(profile: RemotePublicProfile, connectedAt: Date?, isOwner: Bool) {
    self.profile = profile; self.connectedAt = connectedAt; self.isOwner = isOwner
    top15 = Self.select(profile, seconds: 15); top60 = Self.select(profile, seconds: 60)
  }
  var id: UUID { profile.id }
  // Only the practice ledger declares whether these are lifetime statistics.
  // Legacy decoder defaults must not masquerade as known zero statistics.
  var hasStatistics: Bool { profile.practiceHistoryComplete != nil }
  var level: Int? { hasStatistics ? ProfileLevelProgress(totalXP: profile.totalExperience)?.level : nil }
  func best(seconds: Int) -> RemotePublicProfileBest? {
    seconds == 15 ? top15 : seconds == 60 ? top60 : nil
  }
  private static func select(_ profile: RemotePublicProfile, seconds: Int) -> RemotePublicProfileBest? {
    profile.displayPersonalBests.reduce(nil as RemotePublicProfileBest?) { selected, candidate in
      guard candidate.mode == "time", (candidate.mode2 ?? candidate.durationSeconds.map(String.init)) == String(seconds),
        candidate.effectiveWpm.isFinite, candidate.effectiveWpm >= 0 else { return selected }
      // The pinned friend projection chooses the later whole record on ties,
      // across languages/configurations, including a zero-speed record.
      return candidate.effectiveWpm >= (selected?.effectiveWpm ?? 0) ? candidate : selected
    }
  }
}

enum FriendComparisonColumn: String, Codable, CaseIterable {
  case name, connectedAt, experience, completed, typingTime, streak, top15, top60
  var title: String {
    switch self {
    case .name: "用户"
    case .connectedAt: "关系时长"
    case .experience: "等级"
    case .completed: "完成／开始"
    case .typingTime: "练习时长"
    case .streak: "连续天数"
    case .top15: "15 秒 PB"
    case .top60: "60 秒 PB"
    }
  }
  var width: Double {
    switch self {
    case .name: 190
    case .top15, .top60: 135
    default: 100
    }
  }
}

struct FriendComparisonSort: Codable, Equatable {
  let column: FriendComparisonColumn
  var descending: Bool
  static func toggled(_ values: [Self], column: FriendComparisonColumn, adding: Bool) -> [Self] {
    var result = adding ? values : values.filter { $0.column == column }
    if let index = result.firstIndex(where: { $0.column == column }) {
      let firstDescending = column != .name
      if result[index].descending == firstDescending { result[index].descending.toggle() }
      else { result.remove(at: index) }
    } else { result.append(.init(column: column, descending: column != .name)) }
    return result
  }
  static func decode(_ text: String) -> [Self] {
    guard let values = try? JSONDecoder().decode([Self].self, from: Data(text.utf8)),
      values.count <= FriendComparisonColumn.allCases.count,
      Set(values.map(\.column)).count == values.count else { return [] }
    return values
  }
  static func encode(_ values: [Self]) -> String {
    (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
  }
}

enum FriendComparisonPolicy {
  static func rows(_ snapshot: ConnectionsSnapshot, sort: [FriendComparisonSort]) -> [FriendComparisonRow] {
    var rows = snapshot.visibleConnections.filter { $0.relation == .friend }.map {
      FriendComparisonRow(profile: $0.profile, connectedAt: $0.updatedAt, isOwner: false)
    }
    if let owner = snapshot.ownerProfile { rows.append(.init(profile: owner, connectedAt: nil, isOwner: true)) }
    // Retain source order for equal values, independently of sort direction.
    return rows.enumerated().sorted { left, right in
      for descriptor in sort {
        let order: ComparisonResult
        if descriptor.column == .name {
          order = left.element.profile.displayName.localizedStandardCompare(right.element.profile.displayName)
        } else {
          let lhs = value(left.element, column: descriptor.column), rhs = value(right.element, column: descriptor.column)
          // An unknown statistic stays last in both directions, not a fake zero.
          if (lhs == nil) != (rhs == nil) { return lhs != nil }
          order = lhs == rhs ? .orderedSame : (lhs ?? 0) < (rhs ?? 0) ? .orderedAscending : .orderedDescending
        }
        if order != .orderedSame { return descriptor.descending ? order == .orderedDescending : order == .orderedAscending }
      }
      return left.offset < right.offset
    }.map(\.element)
  }
  private static func value(_ row: FriendComparisonRow, column: FriendComparisonColumn) -> Double? {
    switch column {
    case .name: nil
    case .connectedAt: row.connectedAt?.timeIntervalSince1970
    case .experience: row.hasStatistics ? Double(row.profile.totalExperience) : nil
    case .completed: row.hasStatistics ? Double(row.profile.completedResultCount) : nil
    case .typingTime: row.hasStatistics && row.profile.totalTypingSeconds.isFinite ? row.profile.totalTypingSeconds : nil
    case .streak: row.profile.streak.map { Double($0.currentDays) }
    case .top15: row.best(seconds: 15)?.effectiveWpm
    case .top60: row.best(seconds: 60)?.effectiveWpm
    }
  }
  static func streak(_ days: Int?) -> String {
    guard let days, days >= 0, days != 1 else { return "—" }
    return "\(days) 天"
  }
  static func ratio(completed: Int, started: Int) -> String {
    guard started > 0, completed >= 0, completed <= started else { return "完成比例未知" }
    let percent = floor(Double(completed) / Double(started) * 100)
    let restarts = completed == 0 ? "∞" : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(started - completed) / Double(completed))
    return "完成 \(Int(percent))% · 每次完成对应重启 \(restarts) 次"
  }
}
