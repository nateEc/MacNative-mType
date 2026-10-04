import Foundation
import Vapor

/// Raw measured seconds before any source terminal tail trimming. It is
/// anonymous metadata, not attestation or a substitute for real date stamps.
public struct ResultElapsedTime: Content, Equatable, Sendable {
  public let version: Int
  public let seconds: Double

  public init(version: Int = 1, seconds: Double) {
    self.version = version
    self.seconds = seconds
  }

  var isValid: Bool { version == 1 && seconds.isFinite && seconds > 0 && seconds <= 3_600 }

  func duration(mode: String) -> Double {
    mode == "custom" ? seconds : ((seconds + Double.ulpOfOne) * 100).rounded() / 100
  }

  func isDateConsistent(mode: String, bailedOut: Bool, calendarSeconds: Double) -> Bool {
    guard isValid, calendarSeconds.isFinite else { return false }
    let measured = duration(mode: mode)
    guard (1...3_600).contains(measured) else { return false }
    return mode != "time" || bailedOut || measured > 120
      || (measured >= calendarSeconds - 0.1 && measured <= calendarSeconds + 0.1)
  }

  private enum CodingKeys: String, CodingKey { case version, seconds }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    seconds = try values.decode(Double.self, forKey: .seconds)
    guard isValid else {
      throw DecodingError.dataCorruptedError(forKey: .seconds, in: values,
        debugDescription: "Service elapsed time must have version 1 and finite positive seconds no greater than 3600")
    }
  }

  public func encode(to encoder: Encoder) throws {
    guard isValid else {
      throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
        debugDescription: "Invalid elapsed time cannot be emitted as legacy absence"))
    }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(version, forKey: .version)
    try values.encode(seconds, forKey: .seconds)
  }
}

/// Only the explicit new timing contract restores Date precision. The
/// supplement may restore an ISO-lost fraction, never replace a date or epoch.
enum ResultDatePrecision {
  static func restore<Key: CodingKey>(_ date: Date, referenceTime: Double?, required: Bool,
    key: Key, values: KeyedDecodingContainer<Key>) throws -> Date {
    guard required else { return date }
    guard let referenceTime, referenceTime.isFinite, date.timeIntervalSinceReferenceDate.isFinite,
      abs(referenceTime - date.timeIntervalSinceReferenceDate) < 1 else {
      throw DecodingError.dataCorruptedError(forKey: key, in: values,
        debugDescription: "Independent elapsed time requires finite date precision matching each real date")
    }
    return Date(timeIntervalSinceReferenceDate: referenceTime)
  }
}
