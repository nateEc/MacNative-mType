import Foundation

/// Window-local nosave fields outlive challenge identity, but not an explicit
/// application of that field. Event revisions distinguish same-value writes.
@MainActor
struct ChallengeLiveConfigurationState {
  enum ApplicationField { case difficulty, modifiers, font, keyboardGuide }
  private weak var owner: AppSettings?
  private var liveDifficulty: Difficulty?
  private var liveModifiers: [TestModifier]?
  private var difficultyRevision: UInt64?
  private var modifiersRevision: UInt64?
  private var liveFontFamily: String?
  private var liveKeyboardGuide: KeyboardGuideMode?
  private var fontRevision: UInt64?
  private var keyboardGuideRevision: UInt64?

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
    installDisplay(configuration, settings: settings)
    owner = settings
    return true
  }

  /// Legacy setup still applies its existing global fields. It needs the same
  /// event fence, but must not acquire source-only nosave overrides.
  @discardableResult
  mutating func observeLegacyChallenge(settings: AppSettings, configuration: TestConfiguration? = nil) -> Bool {
    guard !settings.hasThresholdProfile else { return false }
    liveDifficulty = nil
    liveModifiers = nil
    difficultyRevision = settings.difficultyApplicationRevision
    modifiersRevision = settings.testModifiersApplicationRevision
    installDisplay(configuration, settings: settings)
    owner = settings
    return true
  }

  private mutating func installDisplay(_ configuration: TestConfiguration?, settings: AppSettings) {
    // A later challenge does not own these fields unless it explicitly sets them.
    let priorFont = hasTransientFont(settings: settings) ? liveFontFamily : nil
    let priorGuide = hasTransientKeyboardGuide(settings: settings) ? liveKeyboardGuide : nil
    let wingdings = configuration?.challengeID == "ten-words-of-pain"
    liveFontFamily = wingdings ? WingdingsChallengeFont.familyName : priorFont
    liveKeyboardGuide = wingdings ? .off : priorGuide
    fontRevision = settings.practiceFontApplicationRevision
    keyboardGuideRevision = settings.keyboardGuideApplicationRevision
  }

  func hasTransientFont(settings: AppSettings) -> Bool {
    owner === settings && liveFontFamily != nil && fontRevision == settings.practiceFontApplicationRevision
  }

  func fontFamilyName(settings: AppSettings) -> String {
    hasTransientFont(settings: settings) ? liveFontFamily ?? settings.installedPracticeFontName : settings.installedPracticeFontName
  }

  func hasTransientKeyboardGuide(settings: AppSettings) -> Bool {
    owner === settings && liveKeyboardGuide != nil && keyboardGuideRevision == settings.keyboardGuideApplicationRevision
  }

  func keyboardGuideMode(settings: AppSettings) -> KeyboardGuideMode {
    hasTransientKeyboardGuide(settings: settings) ? liveKeyboardGuide ?? settings.effectiveKeyboardGuideMode : settings.effectiveKeyboardGuideMode
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
    case .font:
      installed = fontRevision
      current = settings.practiceFontApplicationRevision
    case .keyboardGuide:
      installed = keyboardGuideRevision
      current = settings.keyboardGuideApplicationRevision
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
    snapshot.installedPracticeFontName = fontFamilyName(settings: settings)
    if hasTransientKeyboardGuide(settings: settings) {
      snapshot.keyboardGuideMode = keyboardGuideMode(settings: settings)
      snapshot.showKeyboardGuide = snapshot.keyboardGuideMode != .off
    }
    return snapshot
  }
}
