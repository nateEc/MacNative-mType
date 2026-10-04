import Foundation
import Vapor

/// Anonymous per-attempt accuracy and time. Not an XP award, account context,
/// proof of human typing, or authority to change existing account scores.
public struct ResultIncompletePractice: Content, Equatable, Sendable {
  public struct Attempt: Codable, Equatable, Sendable {
    public let accuracy: Double
    public let seconds: Double
    public init(accuracy: Double, seconds: Double) { self.accuracy = accuracy; self.seconds = seconds }
    var isValid: Bool {
      accuracy.isFinite && (0...100).contains(accuracy) && seconds.isFinite && seconds >= 0
    }
  }
  public let version: Int
  public let attempts: [Attempt]
  public init(version: Int = 1, attempts: [Attempt]) { self.version = version; self.attempts = attempts }
  private var structurallyValid: Bool {
    version == 1 && attempts.count <= 1_000 && attempts.allSatisfy(\.isValid)
      && summedSeconds.isFinite
  }
  var summedSeconds: Double { attempts.reduce(0) { $0 + $1.seconds } }

  func isValid(restartCount: Int, practiceTiming: ResultPracticeTiming?) -> Bool {
    guard structurallyValid, let timing = practiceTiming, timing.version == 1,
      (0...3_600_000).contains(timing.terminalEngagedMilliseconds),
      (0...1_000).contains(restartCount), attempts.count == restartCount,
      (0...(restartCount * 3_600_000)).contains(timing.priorAttemptEngagedMilliseconds) else { return false }
    let prior = Double(timing.priorAttemptEngagedMilliseconds) / 1_000
    if attempts.isEmpty { return prior == 0 }
    // New per-attempt hundredths and the legacy raw-sum millisecond report
    // have different precision. Do not rescore or rewrite either value.
    return abs(summedSeconds - prior) <= Double(restartCount) * 0.005 + 0.0005 + 1e-9
      + max(summedSeconds, prior) * Double.ulpOfOne * 8
  }
  private enum CodingKeys: String, CodingKey { case version, attempts }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    attempts = try values.decode([Attempt].self, forKey: .attempts)
    guard structurallyValid else {
      throw DecodingError.dataCorruptedError(forKey: .attempts, in: values,
        debugDescription: "Incomplete practice needs version 1 and bounded, finite per-attempt values")
    }
  }
}
