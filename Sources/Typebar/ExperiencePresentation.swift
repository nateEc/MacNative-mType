import Foundation

enum ExperiencePresentation {
  static func compact(_ experience: Int) -> String {
    compact(Double(experience))
  }

  /// Fractional receipt/weekly values remain distinct from integral lifetime credit.
  static func compact(_ experience: Double) -> String {
    guard experience.isFinite else { return "—" }
    let magnitude = abs(experience)
    guard magnitude >= 1_000 else {
      if experience.rounded(.towardZero) == experience {
        return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), experience)
      }
      return String(experience)
    }

    let suffixes = ["", "k", "m", "b", "t", "q", "Q"]
    var scaled = magnitude
    var suffixIndex = 0
    while scaled >= 1_000, suffixIndex < suffixes.count - 1 {
      scaled /= 1_000
      suffixIndex += 1
    }

    let sign = experience < 0 ? "-" : ""
    let number = String(
      format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), scaled)
    return "\(sign)\(number)\(suffixes[suffixIndex])"
  }
}
