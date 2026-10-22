import XCTest
@testable import Typebar

@MainActor
final class SourceShareApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults, LocalNoticeCenter) throws -> Void) throws {
    let suite = "typebar.source-share-application.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let notices = LocalNoticeCenter()
    defer { defaults.removePersistentDomain(forName: suite); notices.clearAll() }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumAccuracy(mode: .off, customValue: 93))
    try raw.apply(.minimumWordBurst(mode: .off, customValue: 84))
    var snapshot = PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot(fontSize: 31))
    snapshot.activeResultTags = ["local"]
    defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22)), forKey: "appSettings.v1")
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(snapshot))
    try body(AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory()),
      defaults, notices)
  }

  private func current(_ settings: AppSettings) -> SavedTestPreset {
    .init(configuration: .words(25, rules: settings.inputRules),
      activeResultTags: settings.activeResultTags, settingsSnapshot: settings.snapshot)
  }

  private func apply(_ link: String, settings: AppSettings, notices: LocalNoticeCenter,
    onApplication: (SavedTestPreset) -> Void = { _ in }) -> TestConfigurationShareActionResult {
    TestConfigurationShareActions.apply(link, current: current(settings), challenges: [], notices: notices,
      applyPreset: { preset in
        XCTAssertFalse(notices.history.contains { $0.level == .success })
        onApplication(preset)
        guard PresetSettingsApplication.commit(original: preset, resolved: preset,
          configuration: preset.configuration, to: settings, appliesGlobalSettings: true) else { return nil }
        return preset
      }, loadChallenge: { _ in XCTFail("Ordinary test link"); return .rejected })
  }

  func testSourceV3LinkCommitsRawZeroModesWithoutLocalSettingsOrTags() throws {
    try withSettings { settings, defaults, notices in
      var raw = PracticeThresholdConfiguration()
      try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
      try raw.apply(.minimumAccuracy(mode: .custom, customValue: 0))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      let source = PracticeThresholdSource(configuration: raw)
      let preset = SavedTestPreset(configuration: .words(3,
        rules: source.applying(to: InputRules(strictSpace: true))))
      let oldBytes = defaults.data(forKey: "appSettings.v1")
      let fontRevision = settings.practiceFontApplicationRevision
      var calls = 0
      let result = apply(try TestConfigurationShare.link(for: preset), settings: settings, notices: notices) {
        calls += 1
        XCTAssertNil($0.settingsSnapshot)
        XCTAssertNil($0.activeResultTags)
      }
      XCTAssertEqual(result.outcome, .applied)
      XCTAssertTrue(result.shouldDismiss)
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(settings.thresholdConfiguration, raw)
      XCTAssertEqual(settings.inputRules, preset.configuration.rules)
      XCTAssertEqual(settings.activeResultTags, ["local"])
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), oldBytes)
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(settings.snapshot))
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.thresholdConfiguration, raw)
      var configuration = preset.configuration
      configuration.rules = reader.inputRules
      var session = TestSessionFactory.make(configuration: configuration)
      session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.outcome, .completed)
      XCTAssertEqual(notices.history.last?.level, .success)
    }
  }

  func testLegacyNativePositiveValuesReplaceOnlyTheirActiveMemories() throws {
    try withSettings { settings, _, notices in
      let preset = SavedTestPreset(configuration: .words(3, rules: InputRules(
        strictSpace: true, minimumWpm: 45.5, minimumWordBurstWpm: 88.25, minimumWordBurstMode: .flex)))
      let result = apply(try TestConfigurationShare.link(for: preset), settings: settings, notices: notices)
      XCTAssertEqual(result.outcome, .applied)
      XCTAssertEqual(settings.minimumWpm, 45.5)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 45.5)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyCustomValue, 93)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .flex)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstCustomValue, 88.25)
      XCTAssertTrue(settings.strictSpace)
    }
  }

  func testLegacyNativeDisabledRulesKeepTheCurrentSourceMemories() throws {
    try withSettings { settings, _, notices in
      let before = settings.thresholdConfiguration
      let preset = SavedTestPreset(configuration: .words(3))
      var received: SavedTestPreset?
      let result = apply(try TestConfigurationShare.link(for: preset), settings: settings, notices: notices) {
        received = $0
      }
      XCTAssertEqual(result.outcome, .applied)
      XCTAssertNotNil(received?.configuration.rules.thresholdSource)
      XCTAssertEqual(settings.thresholdConfiguration, before)
      XCTAssertEqual(settings.activeResultTags, ["local"])
    }
  }

  func testWebEightSlotLinkPreservesTheWholeCurrentThresholdSource() throws {
    try withSettings { settings, _, notices in
      let before = settings.thresholdConfiguration
      let link = "https://share.example.test/practice?testSettings=NoIg7g9gTgJgziANAVgAyIHYFcA2PEAuUWApogGYCGOcZIJGA5jgJZwAWSIAtpXASShcAxlAIBiYewgQA+lJkgAukA"
      var received: SavedTestPreset?
      let result = apply(link, settings: settings, notices: notices) { received = $0 }
      XCTAssertEqual(result.outcome, .applied)
      XCTAssertEqual(received?.configuration.wordLimit, 50)
      XCTAssertEqual(settings.thresholdConfiguration, before)
      XCTAssertEqual(settings.activeResultTags, ["local"])
      XCTAssertFalse(notices.history.contains { $0.message.contains("share.example.test") })
    }
  }

  func testSourceChallengeLinkIsRejectedBeforeEitherCallback() throws {
    try withSettings { settings, _, notices in
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
      var calls = 0
      let result = TestConfigurationShareActions.apply(
        "https://share.example.test/?challenge=\(challenge.id)", current: current(settings),
        challenges: [challenge], notices: notices,
        applyPreset: { _ in calls += 1; return nil }, loadChallenge: { _ in calls += 1; return .applied })
      XCTAssertEqual(result.outcome, .rejected)
      XCTAssertFalse(result.shouldDismiss)
      XCTAssertEqual(calls, 0)
      XCTAssertTrue(notices.history.allSatisfy { $0.level != .success })
    }
  }

  func testLiveModelRefusalsNeverProduceSuccessOrChangeProtectedBytes() throws {
    for key in ["appSettings.v4", "activeTestSelection.v2", "lock"] {
      try withSettings { settings, defaults, notices in
        let owner = UUID()
        if key == "lock" { settings.setNoQuitConfigurationLock(true, for: owner) }
        else { defaults.set(Data("{\"version\":99}".utf8), forKey: key) }
        defer { settings.setNoQuitConfigurationLock(false, for: owner) }
        let before = settings.snapshot
        let domain = defaults.dictionaryRepresentation() as NSDictionary
        let link = try TestConfigurationShare.link(for: .init(configuration: .words(3)))
        let result = apply(link, settings: settings, notices: notices)
        XCTAssertEqual(result.outcome, .rejected)
        XCTAssertFalse(result.shouldDismiss)
        XCTAssertEqual(settings.snapshot, before)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
        XCTAssertTrue(notices.history.allSatisfy { $0.level != .success })
      }
    }
  }

  func testCorruptCurrentSourceIsRejectedBeforeApplication() throws {
    try withSettings { settings, _, notices in
      let incoming = SavedTestPreset(configuration: .words(3))
      let link = try TestConfigurationShare.link(for: incoming)
      var inconsistentRules = current(settings)
      inconsistentRules.configuration.rules.minimumWpm = 99
      var missingOwner = current(settings)
      missingOwner.configuration.rules.thresholdSource = nil
      for malformed in [inconsistentRules, missingOwner] {
        let result = TestConfigurationShareActions.apply(link, current: malformed,
          challenges: [], notices: notices,
          applyPreset: { _ in XCTFail("Invalid owner must not reach application"); return nil },
          loadChallenge: { _ in XCTFail("Not a challenge"); return .rejected })
        XCTAssertEqual(result.outcome, .rejected)
        XCTAssertFalse(result.shouldDismiss)
      }
    }
  }

  func testLegacyAdmissionRejectsNoncanonicalRulesInsteadOfClampingThem() throws {
    try withSettings { settings, _, _ in
      let baseline = SavedTestPreset(configuration: .words(3))
      var invalidSpeed = baseline
      invalidSpeed.configuration.rules.minimumWpm = -.infinity
      var invalidAccuracy = baseline
      invalidAccuracy.configuration.rules.minimumAccuracy = 101
      var invalidBurst = baseline
      invalidBurst.configuration.rules.minimumWordBurstWpm = 50
      invalidBurst.configuration.rules.minimumWordBurstMode = .off
      for invalid in [invalidSpeed, invalidAccuracy, invalidBurst] {
        XCTAssertThrowsError(try ShareThresholdAdmission.preparing(invalid, current: current(settings)))
      }
    }
  }

  func testLegacyZeroDisablesExplicitZeroModesWithoutDiscardingTheirMemory() throws {
    try withSettings { settings, _, notices in
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .custom, customValue: 0)))
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumAccuracy(mode: .custom, customValue: 0)))
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWordBurst(mode: .fixed, customValue: 0)))
      let result = apply(try TestConfigurationShare.link(for: .init(configuration: .words(3))),
        settings: settings, notices: notices)
      XCTAssertEqual(result.outcome, .applied)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 0)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyCustomValue, 0)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstCustomValue, 0)
    }
  }

  func testRejectedSourceCallbackCannotClaimSuccess() throws {
    try withSettings { settings, defaults, notices in
      let preset = SavedTestPreset(configuration: .words(3, rules: settings.inputRules))
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      var calls = 0
      let result = TestConfigurationShareActions.apply(try TestConfigurationShare.link(for: preset),
        current: current(settings), challenges: [], notices: notices,
        applyPreset: { _ in calls += 1; return nil }, loadChallenge: { _ in .rejected })
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(result.outcome, .rejected)
      XCTAssertFalse(result.shouldDismiss)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      XCTAssertTrue(notices.history.allSatisfy { $0.level != .success })
    }
  }

  func testSourceNoticeSeparatesRememberedValuesFromEnabledZeroWithoutLeakingText() throws {
    try withSettings { settings, _, notices in
      var raw = try XCTUnwrap(settings.thresholdConfiguration)
      try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
      try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
      let secret = "OWNED_PRIVATE_TEXT"
      let preset = SavedTestPreset(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: PracticeThresholdSource(configuration: raw).applying(to: InputRules())),
        customText: secret)
      let link = try TestConfigurationShare.link(for: preset)
      XCTAssertEqual(apply(link, settings: settings, notices: notices).outcome, .applied)
      let message = try XCTUnwrap(notices.history.last?.message)
      XCTAssertTrue(message.contains("最低整体速度：开启（0 WPM）"))
      XCTAssertTrue(message.contains("最低准确率：关闭（记忆 93%）"))
      XCTAssertTrue(message.contains("最低单词速度：弹性（0 WPM）"))
      XCTAssertFalse(message.contains(secret))
      XCTAssertFalse(message.contains(link))
      XCTAssertTrue(notices.history.allSatisfy { $0.details == nil })
    }
  }

  func testShareSheetReadsCurrentSourceInsteadOfItsOpeningSnapshot() throws {
    try withSettings { settings, _, notices in
      let opening = current(settings)
      let view = TestConfigurationShareView(currentPreset: opening,
        latestPreset: { self.current(settings) }, notices: notices, onApply: { _ in nil })
      XCTAssertTrue(settings.updateThresholdConfiguration(.minimumWpm(mode: .off, customValue: 55)))
      XCTAssertEqual(view.effectiveCurrentPreset.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, 55)
      XCTAssertEqual(opening.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, 37)
      let legacy = SavedTestPreset(configuration: .words(3))
      let prepared = try ShareThresholdAdmission.preparing(legacy, current: view.effectiveCurrentPreset)
      XCTAssertEqual(prepared.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, 55)
    }
  }

  func testVersionOneLinkUsesTheBridgeWithoutRewritingItsLegacyPayload() throws {
    try withSettings { settings, _, notices in
      let preset = SavedTestPreset(configuration: .words(3, rules: InputRules(minimumWpm: 52)))
      let original = try TestConfigurationShare.link(for: preset)
      var url = try XCTUnwrap(URLComponents(string: original))
      var token = try XCTUnwrap(url.queryItems?.first?.value)
        .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      token += String(repeating: "=", count: (4 - token.count % 4) % 4)
      let bytes = try XCTUnwrap(Data(base64Encoded: token))
      var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
      payload["version"] = 1
      let changed = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      url.queryItems = [.init(name: "preset", value: changed)]
      let link = try XCTUnwrap(url.string)
      XCTAssertNil(try TestConfigurationShare.preset(from: link).configuration.rules.thresholdSource)
      XCTAssertEqual(apply(link, settings: settings, notices: notices).outcome, .applied)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 52)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertNil(try TestConfigurationShare.preset(from: link).configuration.rules.thresholdSource)
    }
  }

  func testAdmissionCannotSmuggleLocalMetadataIntoEitherProfileGeneration() throws {
    try withSettings { settings, _, _ in
      let legacy = SavedTestPreset(configuration: .words(3))
      var withTags = legacy
      withTags.activeResultTags = []
      var withSnapshot = legacy
      withSnapshot.settingsSnapshot = .init(fontSize: 99)
      let withScope = legacy.with(settingGroups: [.appearance])
      for current in [legacy, self.current(settings)] {
        for invalid in [withTags, withSnapshot, withScope] {
          XCTAssertThrowsError(try ShareThresholdAdmission.preparing(invalid, current: current))
        }
      }
    }
  }
}
