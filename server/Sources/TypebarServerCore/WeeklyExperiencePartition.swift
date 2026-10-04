import Foundation

public enum WeeklyExperienceConfigurationError: Error {
  case invalidTimeZone
}

/// A receipt of the server's week-key calculation, not an ISO week interval.
/// Saved offsets make validation independent of subsequent time-zone database updates.
struct WeeklyExperiencePartition: Codable, Equatable {
  let version: Int
  let acceptedMilliseconds: Int
  let timeZoneIdentifier: String
  let anchorOffsetSeconds: Int
  let projectedOffsetSeconds: Int
  let gapSeconds: Int
  let keyMilliseconds: Int

  static let day = 86_400_000
  static let week = 7 * day
  private static let dateLimit = 8_640_000_000_000_000

  static func configuredTimeZone(_ identifier: String?) throws -> TimeZone {
    guard let identifier else { return .current }
    guard !identifier.isEmpty, let zone = TimeZone(identifier: identifier) else {
      throw WeeklyExperienceConfigurationError.invalidTimeZone
    }
    return zone
  }

  private static func milliseconds(_ date: Date) throws -> Int {
    let value = date.timeIntervalSince1970 * 1_000
    guard value.isFinite, abs(value) <= Double(dateLimit) else {
      throw ExperienceCalculationError.invalidInput
    }
    return Int(value.rounded(.towardZero))
  }

  // JavaScript's signed remainder is intentional, including before the epoch.
  private static func dayAnchor(_ milliseconds: Int) -> Int {
    milliseconds - milliseconds % day
  }

  private static func weekday(_ wallMilliseconds: Int) -> Int {
    let days = Int(floor(Double(wallMilliseconds) / Double(day)))
    let sundayIndex = ((days + 4) % 7 + 7) % 7
    return sundayIndex == 0 ? 7 : sundayIndex
  }

  static func capture(at acceptedAt: Date, timeZone: TimeZone) throws -> Self {
    let accepted = try milliseconds(acceptedAt)
    let anchor = dayAnchor(accepted)
    let anchorDate = Date(timeIntervalSince1970: Double(anchor) / 1_000)
    let anchorOffset = timeZone.secondsFromGMT(for: anchorDate)
    let localAnchor = anchor + anchorOffset * 1_000
    let shift = 1 - weekday(localAnchor)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var target = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchorDate)
    target.day = target.day! + shift
    guard let projectedDate = calendar.date(from: target) else {
      throw ExperienceCalculationError.invalidInput
    }
    let projected = try milliseconds(projectedDate)
    let projectedOffset = timeZone.secondsFromGMT(for: projectedDate)
    let intendedWall = localAnchor + shift * day
    let gap = projected + projectedOffset * 1_000 - intendedWall
    guard gap % 1_000 == 0 else { throw ExperienceCalculationError.invalidInput }
    let record = Self(version: 1, acceptedMilliseconds: accepted,
      timeZoneIdentifier: timeZone.identifier, anchorOffsetSeconds: anchorOffset,
      projectedOffsetSeconds: projectedOffset, gapSeconds: gap / 1_000,
      keyMilliseconds: dayAnchor(projected))
    try record.validate(acceptedAt: acceptedAt)
    return record
  }

  func validate(acceptedAt: Date?) throws {
    guard version == 1, let acceptedAt,
      acceptedAt.timeIntervalSince1970.isFinite,
      abs(acceptedAt.timeIntervalSince1970) <= Double(Self.dateLimit) / 1_000,
      // Existing ISO-8601 store dates retain whole seconds. The partition keeps
      // the clipped millisecond clock; bind both to the same persisted second.
      Int(floor(acceptedAt.timeIntervalSince1970)) == Int(floor(Double(acceptedMilliseconds) / 1_000)),
      abs(Double(acceptedMilliseconds)) <= Double(Self.dateLimit),
      !timeZoneIdentifier.isEmpty, timeZoneIdentifier.utf8.count <= 128,
      (-86_400...86_400).contains(anchorOffsetSeconds),
      (-86_400...86_400).contains(projectedOffsetSeconds),
      (0...86_400).contains(gapSeconds) else {
      throw ExperienceCalculationError.invalidInput
    }
    let anchor = Self.dayAnchor(acceptedMilliseconds)
    let wall = anchor + anchorOffsetSeconds * 1_000
    let projection = wall + (1 - Self.weekday(wall)) * Self.day
      - projectedOffsetSeconds * 1_000 + gapSeconds * 1_000
    guard abs(projection) <= Self.dateLimit,
      keyMilliseconds == Self.dayAnchor(projection) else {
      throw ExperienceCalculationError.invalidInput
    }
  }
}
