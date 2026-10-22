import Foundation

/// Challenge setup owns its mode, limits and difficulty, not the user's input
/// rules. Reuse this projection for submission and every session rebuild.
enum ChallengeInputRulePolicy {
  static func applying(_ rules: InputRules, to template: TestConfiguration) -> TestConfiguration {
    var configuration = template
    configuration.rules = rules
    return configuration
  }
}
