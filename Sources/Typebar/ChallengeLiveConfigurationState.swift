import Foundation

/// Window-local nosave fields outlive challenge identity, but not an explicit
/// application of that field. Event revisions distinguish same-value writes.
@MainActor
struct ChallengeLiveConfigurationState {
  private var liveDifficulty: Difficulty?
  private var liveModifiers: [TestModifier]?
  private var difficultyRevision: UInt64?
  private var modifiersRevision: UInt64?

  @discardableResult
  mutating func install(_ configuration: TestConfiguration, settings: AppSettings) -> Bool {
    guard settings.hasThresholdProfile, case .available(let stored) = settings.thresholdProfileRead,
      let source = settings.inputRules.thresholdSource, stored.thresholdSource == source,
      configuration.challengeID != nil,
      configuration.rules == settings.inputRules else { return false }
    liveDifficulty = configuration.difficulty
    liveModifiers = configuration.modifiers
    difficultyRevision = settings.difficultyApplicationRevision
    modifiersRevision = settings.testModifiersApplicationRevision
    return true
  }

  func difficulty(settings: AppSettings) -> Difficulty {
    settings.hasThresholdProfile && difficultyRevision == settings.difficultyApplicationRevision
      ? liveDifficulty ?? settings.difficulty : settings.difficulty
  }

  func hasTransientModifiers(settings: AppSettings) -> Bool {
    settings.hasThresholdProfile && liveModifiers != nil
      && modifiersRevision == settings.testModifiersApplicationRevision
  }

  func modifiers(settings: AppSettings) -> [TestModifier] {
    hasTransientModifiers(settings: settings) ? liveModifiers ?? [] : settings.testModifiers
  }

  mutating func normalizeModifiers(_ modifiers: [TestModifier], settings: AppSettings) {
    guard hasTransientModifiers(settings: settings) else { return }
    liveModifiers = modifiers
  }

  func snapshot(settings: AppSettings) -> AppSettingsSnapshot {
    var snapshot = settings.snapshot
    snapshot.difficulty = difficulty(settings: settings)
    snapshot.testModifiers = modifiers(settings: settings)
    return snapshot
  }
}
