import Foundation

/// Window-local nosave fields outlive challenge identity, but not an explicit
/// application of that field. Event revisions distinguish same-value writes.
@MainActor
struct ChallengeLiveConfigurationState {
  enum ApplicationField { case difficulty, modifiers }
  private weak var owner: AppSettings?
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
    owner = settings
    return true
  }

  /// Legacy setup still applies its existing global fields. It needs the same
  /// event fence, but must not acquire source-only nosave overrides.
  @discardableResult
  mutating func observeLegacyChallenge(settings: AppSettings) -> Bool {
    guard !settings.hasThresholdProfile else { return false }
    owner = settings
    liveDifficulty = nil
    liveModifiers = nil
    difficultyRevision = settings.difficultyApplicationRevision
    modifiersRevision = settings.testModifiersApplicationRevision
    return true
  }

  func difficulty(settings: AppSettings) -> Difficulty {
    owner === settings && settings.hasThresholdProfile && difficultyRevision == settings.difficultyApplicationRevision
      ? liveDifficulty ?? settings.difficulty : settings.difficulty
  }

  func hasTransientModifiers(settings: AppSettings) -> Bool {
    owner === settings && settings.hasThresholdProfile && liveModifiers != nil
      && modifiersRevision == settings.testModifiersApplicationRevision
  }

  func modifiers(settings: AppSettings) -> [TestModifier] {
    hasTransientModifiers(settings: settings) ? liveModifiers ?? [] : settings.testModifiers
  }

  /// Own setup is installed after its writes, so its queued notifications have
  /// the captured revision. Ignore older deliveries and events from a different model.
  func shouldClearChallenge(for field: ApplicationField, eventRevision: UInt64,
    settings: AppSettings) -> Bool {
    guard owner === settings else { return false }
    let installed: UInt64?
    let current: UInt64
    switch field {
    case .difficulty:
      installed = difficultyRevision
      current = settings.difficultyApplicationRevision
    case .modifiers:
      installed = modifiersRevision
      current = settings.testModifiersApplicationRevision
    }
    guard let installed else { return false }
    return eventRevision == current && installed != current
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
