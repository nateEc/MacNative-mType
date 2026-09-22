import Foundation

enum ExperiencePresentation {
  /// Keeps leaderboard values compact while preserving the stored XP integer unchanged.
  static func compact(_ experience: Int) -> String {
    let magnitude = abs(Double(experience))
    guard magnitude >= 1_000 else { return "\(experience)" }

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
