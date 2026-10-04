import Foundation
import Vapor

/// Anonymous clock evidence for new Zen/BailOut submissions, not text or competitive
/// proof. Legacy records without it keep their original wall-clock denominator.
public struct ResultTerminalTiming: Content, Equatable, Sendable {
  public let version: Int
  public let endMilliseconds: Double
  public let lastKeypressMilliseconds: Double?

  public init(version: Int, endMilliseconds: Double, lastKeypressMilliseconds: Double?) {
    self.version = version
    self.endMilliseconds = endMilliseconds
    self.lastKeypressMilliseconds = lastKeypressMilliseconds
  }

  public var measuredSeconds: Double {
    rounded(boundarySeconds)
  }

  public func duration(mode: String) -> Double {
    mode == "custom" ? boundarySeconds : measuredSeconds
  }

  private var boundarySeconds: Double {
    let gap = lastKeypressMilliseconds.map { rounded(endMilliseconds - $0) }
    let clipped = gap.map { $0 < 7_000 ? max(0, $0) : 0 } ?? 0
    return max(0, endMilliseconds - clipped) / 1_000
  }

  func isValid(wallClockSeconds: Double, mode: String, bailedOut: Bool = false,
    independentElapsedTime: Bool = false) -> Bool {
    // Legacy ISO dates can lose <1s. Explicit independent evidence keeps the
    // precise raw boundary and permits a rounded 1s quote from a subsecond raw.
    let rawIsValid = independentElapsedTime
      ? wallClockSeconds > 0 && wallClockSeconds <= 3_600 : (1...3_600).contains(wallClockSeconds)
    let toleranceMilliseconds = independentElapsedTime ? 0.011 : 1_000.011
    guard version == 1, mode == "zen" || bailedOut, wallClockSeconds.isFinite,
      rawIsValid, endMilliseconds.isFinite,
      (0...3_600_000).contains(endMilliseconds),
      abs(endMilliseconds - wallClockSeconds * 1_000) <= toleranceMilliseconds
    else { return false }
    if let lastKeypressMilliseconds {
      guard lastKeypressMilliseconds.isFinite, lastKeypressMilliseconds <= endMilliseconds,
        (endMilliseconds - lastKeypressMilliseconds).isFinite else { return false }
    }
    return ((bailedOut ? 1.0 : 15.0)...3_600).contains(duration(mode: mode))
  }

  private func rounded(_ value: Double) -> Double {
    guard value.isFinite, abs(value) <= Double.greatestFiniteMagnitude / 100 else { return value }
    return ((value + Double.ulpOfOne) * 100).rounded() / 100
  }
}
