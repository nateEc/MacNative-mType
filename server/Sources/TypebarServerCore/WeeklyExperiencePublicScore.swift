import Foundation

/// Public integer projection, not a change to the persisted fractional award.
/// The pinned Redis 6.2.6 RESP2 score and Lua friends-list number encodings have
/// different precision; the original service parses their decimal prefix.
enum WeeklyExperiencePublicScore {
  static func project(_ score: Double, friendsList: Bool = false) -> Double {
    // No Locale argument: Foundation's locale-aware formatter changes %g's
    // precision/exponent behavior even with en_US_POSIX. Use its C-format path.
    let encoded = String(format: friendsList ? "%.14g" : "%.17g", score)
    let integerPrefix = encoded.prefix { $0 >= "0" && $0 <= "9" }
    // Callers supply validated nonnegative finite ledger totals only.
    return Double(integerPrefix)!
  }
}
