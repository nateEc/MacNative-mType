import Foundation
import Vapor

/// Completion configuration only; never transports custom text or replay.
public struct ResultCustomLimit: Content, Equatable, Sendable {
  public let mode: String
  public let value: Int

  public init(mode: String, value: Int) { self.mode = mode; self.value = value }

  var isValid: Bool {
    ["word", "section", "time", "none"].contains(mode)
      && (0...9_007_199_254_740_991).contains(value)
      && (mode != "none" || value == 0)
  }
}

enum ResultBailoutPolicy {
  /// Nil is a legacy/completed result, not permission to discard new context.
  static func hasValidContext(bailedOut: Bool?, mode: String, duration: Int?, words: Int?,
    custom: ResultCustomLimit?) -> Bool {
    guard bailedOut == true else { return custom == nil }
    let safe = 0...9_007_199_254_740_991
    switch mode {
    case "time": return duration.map(safe.contains) == true && words == nil && custom == nil
    case "words": return words.map(safe.contains) == true && duration == nil && custom == nil
    case "custom": return custom?.isValid == true
    case "zen", "quote": return custom == nil
    default: return false
    }
  }

  static func isLongEnough(mode: String, duration: Int?, words: Int?, custom: ResultCustomLimit?,
    measured: Double) -> Bool {
    guard measured.isFinite, (1...3_600).contains(measured) else { return false }
    switch mode {
    case "time": return measured >= 15 && duration.map { $0 == 0 || $0 >= 15 } == true
    case "words": return measured >= 15 && words.map { $0 == 0 || $0 >= 10 } == true
    case "custom":
      guard let custom, custom.isValid, measured >= 15 else { return false }
      switch custom.mode {
      case "word", "section": return custom.value >= 10
      case "time": return custom.value >= 15
      default: return true
      }
    case "zen": return measured >= 15
    case "quote": return true
    default: return false
    }
  }
}
