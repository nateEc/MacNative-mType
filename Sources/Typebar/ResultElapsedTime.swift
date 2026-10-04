import Foundation

/// A completed attempt's raw measured duration, before terminal tail trimming.
/// Calendar dates remain real dates; clock origins and instants are not saved.
/// Absence preserves legacy date-derived duration without backfilling it.
struct ResultElapsedTime: Codable, Equatable, Sendable {
  // Native persistence limit, not a test-mode duration or a source policy.
  // Leave room below Int's millisecond boundary for floating-point rounding.
  static let maximumSeconds = TimeInterval(Int.max / 1_000 - 1)
  let version: Int
  let seconds: TimeInterval

  init(version: Int = 1, seconds: TimeInterval) {
    self.version = version
    self.seconds = seconds
  }

  var isValid: Bool {
    version == 1 && seconds.isFinite && (0...Self.maximumSeconds).contains(seconds)
  }

  func duration(mode: TestMode) -> TimeInterval {
    mode == .custom ? seconds : ResultTerminalTiming.round(seconds)
  }

  /// New service submissions use measured time without bypassing the source's
  /// ordinary short-time calendar consistency check. Legacy absence is separate.
  func isServiceCompatible(mode: TestMode, bailedOut: Bool, calendarSeconds: Double) -> Bool {
    guard isValid, seconds > 0, seconds <= 3_600, calendarSeconds.isFinite else { return false }
    let measured = duration(mode: mode)
    guard (1...3_600).contains(measured) else { return false }
    return mode != .time || bailedOut || measured > 120
      || (measured >= calendarSeconds - 0.1 && measured <= calendarSeconds + 0.1)
  }

  private enum CodingKeys: String, CodingKey { case version, seconds }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    seconds = try values.decode(TimeInterval.self, forKey: .seconds)
    guard isValid else {
      throw DecodingError.dataCorruptedError(forKey: .seconds, in: values,
        debugDescription: "Elapsed time must have version 1 and representable nonnegative seconds")
    }
  }

  func encode(to encoder: Encoder) throws {
    guard isValid else {
      throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
        debugDescription: "Invalid elapsed time must not be encoded as legacy absence"))
    }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version)
    try values.encode(seconds, forKey: .seconds)
  }
}
