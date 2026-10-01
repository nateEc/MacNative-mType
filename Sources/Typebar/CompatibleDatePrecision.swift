import Foundation

/// Retains legacy Date fields while preserving Foundation's actual reference
/// interval. ISO archive dates lose fractions; converting through the Unix
/// epoch can also lose a low bit of Date's underlying Double.
enum CompatibleDatePrecision {
  static func encode<Key: CodingKey>(_ date: Date,
    into values: inout KeyedEncodingContainer<Key>, legacyKey: Key, precisionKey: Key) throws {
    let referenceTime = date.timeIntervalSinceReferenceDate
    guard referenceTime.isFinite else {
      throw EncodingError.invalidValue(date, .init(codingPath: values.codingPath + [precisionKey],
        debugDescription: "Date reference interval must be finite"))
    }
    try values.encode(date, forKey: legacyKey)
    try values.encode(referenceTime, forKey: precisionKey)
  }

  static func decode<Key: CodingKey>(from values: KeyedDecodingContainer<Key>,
    legacyKey: Key, precisionKey: Key) throws -> Date {
    let legacy = try values.decode(Date.self, forKey: legacyKey)
    guard let referenceTime = try values.decodeIfPresent(Double.self, forKey: precisionKey) else {
      return legacy
    }
    // Supplemental precision may restore a lost fraction, not substitute a
    // different date, infer an epoch, or repair an already-truncated archive.
    guard referenceTime.isFinite, legacy.timeIntervalSinceReferenceDate.isFinite,
      abs(referenceTime - legacy.timeIntervalSinceReferenceDate) < 1 else {
      throw DecodingError.dataCorruptedError(forKey: precisionKey, in: values,
        debugDescription: "Date precision disagrees with the legacy date")
    }
    return Date(timeIntervalSinceReferenceDate: referenceTime)
  }
}
