import Foundation

/// The same progression curve, evaluated with integer thresholds so a floating
/// square-root rounding error cannot assign a level before its XP threshold.
struct ProfileLevelProgress: Equatable {
  let totalXP: Int
  let level: Int
  let earnedXP: Int
  let requiredXP: Int
  var remainingXP: Int { requiredXP - earnedXP }
  var fraction: Double { Double(earnedXP) / Double(requiredXP) }
  var percentText: String { String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), fraction * 100) }

  init?(totalXP: Int) {
    guard (0...9_007_199_254_740_991).contains(totalXP) else { return nil }
    func threshold(_ level: Int) -> Int {
      let steps = level - 1
      return steps * 100 + 49 * steps * (steps - 1) / 2
    }
    var lower = 1
    var upper = Int(ceil(sqrt(Double(totalXP) / 24.5))) + 3
    while upper - lower > 1 {
      let middle = lower + (upper - lower) / 2
      if threshold(middle) <= totalXP { lower = middle } else { upper = middle }
    }
    self.totalXP = totalXP; level = lower
    earnedXP = totalXP - threshold(lower)
    requiredXP = 100 + 49 * (lower - 1)
  }
}

struct RemoteAccountStreakClaim: Codable, Equatable, Sendable {
  let version: Int
  let lastResultMilliseconds: Double?
  let streakReferenceMilliseconds: Double?
  let dayBoundaryOffsetHours: Double?

  private enum CodingKeys: String, CodingKey {
    case version, lastResultMilliseconds, streakReferenceMilliseconds, dayBoundaryOffsetHours
  }
  init(version: Int = 1, lastResultMilliseconds: Double?, streakReferenceMilliseconds: Double?, dayBoundaryOffsetHours: Double?) {
    self.version = version; self.lastResultMilliseconds = lastResultMilliseconds
    self.streakReferenceMilliseconds = streakReferenceMilliseconds; self.dayBoundaryOffsetHours = dayBoundaryOffsetHours
  }
  var isValid: Bool {
    version == 1 && [lastResultMilliseconds, streakReferenceMilliseconds].allSatisfy {
      $0.map { $0.isFinite && (0...8_640_000_000_000_000).contains($0) } ?? true
    } && (dayBoundaryOffsetHours.map { $0.isFinite && (-11...12).contains($0) && ($0 * 2).rounded() == $0 * 2 } ?? true)
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version),
      lastResultMilliseconds: try values.decodeIfPresent(Double.self, forKey: .lastResultMilliseconds),
      streakReferenceMilliseconds: try values.decodeIfPresent(Double.self, forKey: .streakReferenceMilliseconds),
      dayBoundaryOffsetHours: try values.decodeIfPresent(Double.self, forKey: .dayBoundaryOffsetHours))
    guard isValid else { throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Invalid owner streak claim") }
  }
}

struct AccountStreakClaimPresentation: Equatable {
  static func isVisible(profileID: UUID, isAccountOverview: Bool, userID: UUID?) -> Bool {
    isAccountOverview && userID == profileID
  }
  enum Status: Equatable { case unavailable, noSavedResult, claimed, available, expired, clockMismatch }
  let status: Status
  let hasSavedToday: Bool?
  let nextBoundaryMilliseconds: Double?
  let lostAtMilliseconds: Double?
  let referenceDiffersFromLastSave: Bool
  let offsetHours: Double?

  init(claim: RemoteAccountStreakClaim?, now: Date) {
    offsetHours = claim?.dayBoundaryOffsetHours
    referenceDiffersFromLastSave = claim?.streakReferenceMilliseconds != nil
      && claim?.streakReferenceMilliseconds != claim?.lastResultMilliseconds
    let milliseconds = now.timeIntervalSince1970 * 1_000
    guard let claim, claim.isValid, milliseconds.isFinite,
      (0...8_640_000_000_000_000).contains(milliseconds) else {
      status = .unavailable; hasSavedToday = nil; nextBoundaryMilliseconds = nil; lostAtMilliseconds = nil; return
    }
    guard [claim.lastResultMilliseconds, claim.streakReferenceMilliseconds].compactMap({ $0 })
      .allSatisfy({ $0 <= milliseconds }) else {
      status = .clockMismatch; hasSavedToday = nil; nextBoundaryMilliseconds = nil; lostAtMilliseconds = nil; return
    }
    let day = 86_400_000.0, offset = (claim.dayBoundaryOffsetHours ?? 0) * 3_600_000
    func start(_ value: Double) -> Double { value - (value - offset).truncatingRemainder(dividingBy: day) }
    let today = start(milliseconds)
    nextBoundaryMilliseconds = today + day
    hasSavedToday = claim.lastResultMilliseconds.map { start($0) == today } ?? false
    guard claim.lastResultMilliseconds != nil else {
      status = .noSavedResult; lostAtMilliseconds = nil; return
    }
    guard let reference = claim.streakReferenceMilliseconds ?? claim.lastResultMilliseconds else {
      status = .noSavedResult; lostAtMilliseconds = nil; return
    }
    let referenceDay = start(reference)
    lostAtMilliseconds = referenceDay + 2 * day
    if referenceDay == today { status = .claimed }
    else if referenceDay == start(milliseconds - day) { status = .available }
    else { status = .expired }
  }

  var heading: String {
    switch status {
    case .unavailable: "连续状态暂不可用"
    case .noSavedResult: "尚无已保存成绩"
    case .claimed: "本连续日已记账"
    case .available: "今天可以延续连续记录"
    case .expired: "连续记录已过期，等待下次保存更新"
    case .clockMismatch: "设备时间与服务记录不一致"
    }
  }
  static func duration(milliseconds: Double) -> String {
    guard milliseconds.isFinite else { return "未知" }
    let seconds = Int(min(8_640_000_000_000, max(0, milliseconds / 1000)).rounded(.up))
    if seconds >= 86_400 { return "\(seconds / 86_400) 天 \(seconds / 3600 % 24) 小时" }
    if seconds >= 3600 { return "\(seconds / 3600) 小时 \(seconds / 60 % 60) 分钟" }
    if seconds >= 60 { return "\(seconds / 60) 分钟 \(seconds % 60) 秒" }
    return "\(seconds) 秒"
  }
}
