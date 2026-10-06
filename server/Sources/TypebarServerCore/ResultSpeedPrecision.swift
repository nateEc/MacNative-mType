import Vapor

/// Source-style completed speed. Integer fields remain an older wire view;
/// this report is authoritative for new selection, scoring and presentation.
public struct ResultSpeedPrecision: Content, Equatable, Sendable {
  public let version: Int
  public let wpm: Double
  public let rawWpm: Double
  public init(version: Int = 1, wpm: Double, rawWpm: Double) {
    self.version = version; self.wpm = wpm; self.rawWpm = rawWpm
  }
  static func round(_ value: Double) -> Double { ((value + Double.ulpOfOne) * 100).rounded() / 100 }
  static func isCanonical(_ value: Double) -> Bool {
    value.isFinite && (0...420).contains(value) && abs(round(value) - value) <= 1e-9
  }
  var isValid: Bool { version == 1 && Self.isCanonical(wpm) && Self.isCanonical(rawWpm) && rawWpm >= wpm }
  func matches(wpm: Int, rawWpm: Int) -> Bool {
    isValid && Int(self.wpm.rounded()) == wpm && Int(self.rawWpm.rounded()) == rawWpm
  }
  func matchesCounters(_ metrics: ResultInputMetrics?, duration: Double, events: Int, errors: Int) -> Bool {
    guard isValid, duration.isFinite, duration > 0, duration <= 3_600,
      (0...1_800_000).contains(events), (0...events).contains(errors), metrics?.isValid != false else { return false }
    if let metrics, metrics.version == 1 ? metrics.retainedUnits < events : metrics.totalAttempts < events { return false }
    let credited = metrics?.creditedUnits ?? events - errors, retained = metrics?.retainedUnits ?? events
    return abs(wpm - Self.round(Double(credited) / 5 / duration * 60)) <= 0.005001
      && abs(rawWpm - Self.round(Double(retained) / 5 / duration * 60)) <= 0.005001
  }
  private enum CodingKeys: String, CodingKey { case version, wpm, rawWpm }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    self.init(version:try values.decode(Int.self,forKey:.version),
      wpm:try values.decode(Double.self,forKey:.wpm),rawWpm:try values.decode(Double.self,forKey:.rawWpm))
    guard isValid else { throw DecodingError.dataCorruptedError(forKey:.wpm,in:values,
      debugDescription:"Unsupported or invalid speed precision") }
  }
}
