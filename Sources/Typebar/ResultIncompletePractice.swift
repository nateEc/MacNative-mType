import Foundation

/// Anonymous XP evidence, independent of the legacy practice-time aggregate.
/// Absence means unknown history; an empty snapshot means explicitly no history.
struct ResultIncompletePractice: Codable, Equatable {
  struct Attempt: Codable, Equatable {
    let accuracy: Double
    let seconds: TimeInterval

    var isValid: Bool {
      accuracy.isFinite && (0...100).contains(accuracy) && seconds.isFinite && seconds >= 0
    }

    static func captured(accuracy: Double, engagedDuration: TimeInterval) -> Attempt? {
      let value = Attempt(accuracy: rounded(accuracy), seconds: rounded(engagedDuration))
      return accuracy.isFinite && (0...100).contains(accuracy)
        && engagedDuration.isFinite && engagedDuration >= 0 && value.isValid ? value : nil
    }

    private static func rounded(_ value: Double) -> Double {
      ((value + Double.ulpOfOne) * 100).rounded() / 100
    }
  }

  let version: Int
  private(set) var attempts: [Attempt]
  static let empty = Self(attempts: [])

  init(version: Int = 1, attempts: [Attempt]) {
    self.version = version
    self.attempts = attempts
  }

  mutating func append(_ attempt: Attempt) { attempts.append(attempt) }

  var summedSeconds: TimeInterval { attempts.reduce(0) { $0 + $1.seconds } }

  func isValid(restartCount: Int, engagedDuration: TimeInterval) -> Bool {
    guard version == 1, restartCount >= 0, attempts.count == restartCount,
      attempts.allSatisfy(\.isValid), engagedDuration.isFinite, engagedDuration >= 0
    else { return false }
    let sum = summedSeconds
    guard sum.isFinite else { return false }
    if attempts.isEmpty { return engagedDuration == 0 }
    // Each new source-style attempt rounds to hundredths; the pre-existing
    // native practice-time sum retains its raw precision. Do not rescore it.
    let tolerance = Double(attempts.count) * 0.005 + 1e-9
      + max(sum, engagedDuration) * Double.ulpOfOne * 8
    return abs(sum - engagedDuration) <= tolerance
  }

  private enum CodingKeys: String, CodingKey { case version, attempts }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    attempts = try values.decode([Attempt].self, forKey: .attempts)
    guard version == 1, attempts.allSatisfy(\.isValid), summedSeconds.isFinite else {
      throw DecodingError.dataCorruptedError(forKey: .attempts, in: values,
        debugDescription: "Incomplete practice needs supported, finite accuracy and seconds")
    }
  }
}
