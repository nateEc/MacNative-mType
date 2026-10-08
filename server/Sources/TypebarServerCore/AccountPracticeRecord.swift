import Foundation
import Vapor

public struct AccountActivityYearsResponse: Content, Equatable {
  public let id: UUID
  public let activityByYear: [String: [Int?]]
  public let practiceHistoryComplete: Bool
}

/// Account lifetime state, deliberately independent of deletable result history.
/// Missing historical evidence is disclosed, never reconstructed from XP.
struct AccountPracticeRecord: Codable, Equatable, Sendable {
  var version = 1
  var completedTests = 0
  var startedTests = 0
  var typingSeconds = 0.0
  var historyComplete = true
  var streakLength = 0
  var maximumStreakLength = 0
  var lastResultMilliseconds = 0.0
  var activityByYear: [String: [Int?]] = [:]

  private static let maximum = 9_007_199_254_740_991.0
  static var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  mutating func record(restarts: Int, seconds: Double, at now: Date, offsetHours: Double) throws {
    guard restarts >= 0, seconds.isFinite, seconds >= 0,
      Double(startedTests) + Double(restarts) + 1 <= Self.maximum,
      Double(completedTests) + 1 <= Self.maximum,
      typingSeconds + seconds <= Self.maximum else { throw ExperienceCalculationError.unsafeArithmetic }
    startedTests += restarts + 1
    completedTests += 1
    typingSeconds += seconds
    let milliseconds = now.timeIntervalSince1970 * 1_000
    let offset = offsetHours * 3_600_000
    func day(_ value: Double) -> Double {
      value - (value - offset).truncatingRemainder(dividingBy: 86_400_000)
    }
    if day(lastResultMilliseconds) == day(milliseconds - 86_400_000) {
      streakLength += 1
    } else if day(lastResultMilliseconds) != day(milliseconds) {
      streakLength = 1
    }
    maximumStreakLength = max(maximumStreakLength, streakLength)
    lastResultMilliseconds = milliseconds
    // Activity is UTC; the independently chosen streak boundary never shifts it.
    let calendar = Self.utc
    let year = calendar.component(.year, from: now)
    guard let ordinal = calendar.ordinality(of: .day, in: .year, for: now) else {
      throw ExperienceCalculationError.invalidInput
    }
    var counts = activityByYear[String(year)] ?? []
    if counts.count < ordinal { counts += Array(repeating: nil, count: ordinal - counts.count) }
    counts[ordinal - 1] = (counts[ordinal - 1] ?? 0) + 1
    activityByYear[String(year)] = counts
    try validate()
  }

  func activity(endingAt now: Date) -> PublicProfileActivityResponse? {
    let calendar = Self.utc
    let year = calendar.component(.year, from: now)
    guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
      let previousFirst = calendar.date(byAdding: .year, value: -1, to: first),
      let previousDays = calendar.range(of: .day, in: .year, for: previousFirst),
      activityByYear[String(year)] != nil || activityByYear[String(year - 1)] != nil
    else { return nil }
    let current = activityByYear[String(year)] ?? []
    var previous = activityByYear[String(year - 1)] ?? []
    previous += Array(repeating: nil, count: previousDays.count - previous.count)
    previous = Array(previous.suffix(372 - current.count))
    guard let lastDay = calendar.date(byAdding: .day, value: current.count - 1, to: first) else { return nil }
    return .init(lastDay: lastDay, testsByDays: previous + current, dayBoundaryOffsetHours: 0)
  }

  func validate() throws {
    guard version == 1, completedTests >= 0, startedTests >= completedTests,
      Double(startedTests) <= Self.maximum, typingSeconds.isFinite,
      (0...Self.maximum).contains(typingSeconds), streakLength >= 0,
      maximumStreakLength >= streakLength, maximumStreakLength <= completedTests,
      lastResultMilliseconds.isFinite, (0...Self.maximum).contains(lastResultMilliseconds)
    else { throw ExperienceCalculationError.invalidInput }
    var total = 0.0
    for (key, counts) in activityByYear {
      guard let year = Int(key), String(year) == key, (1970...9999).contains(year),
        let first = Self.utc.date(from: DateComponents(year: year, month: 1, day: 1)),
        let range = Self.utc.range(of: .day, in: .year, for: first),
        !counts.isEmpty, counts.count <= range.count, counts.last! != nil,
        counts.compactMap({ $0 }).allSatisfy({ $0 > 0 && Double($0) <= Self.maximum })
      else { throw ExperienceCalculationError.invalidInput }
      total += counts.compactMap { $0 }.reduce(0.0) { $0 + Double($1) }
    }
    guard total == Double(completedTests) else { throw ExperienceCalculationError.invalidInput }
  }
}
