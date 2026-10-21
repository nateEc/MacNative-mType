import XCTest

@testable import Typebar

@MainActor
final class ThresholdWholeApplicationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.threshold-whole-apply.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var old = PracticeThresholdConfiguration()
    try old.apply(.minimumWpm(mode: .off, customValue: 37))
    XCTAssertTrue(
      ThresholdSettingsStore(defaults: defaults).save(
        PracticeThresholdSource(configuration: old).applying(to: AppSettingsSnapshot(fontSize: 31)))
    )
    let sound = TypingFeedbackSound(loadSound: { _ in nil }, beep: {})
    try body(
      AppSettings(defaults: defaults, feedbackSound: sound, localBackgroundStore: .inMemory()),
      defaults)
  }

  private func incomingSource() throws -> PracticeThresholdSource {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .custom, customValue: 0))
    try raw.apply(.minimumAccuracy(mode: .custom, customValue: 88.25))
    try raw.apply(.minimumWordBurst(mode: .fixed, customValue: 0))
    return .init(configuration: raw)
  }

  func testWholeSourceSnapshotAppliesLosslesslyAndKeepsOldStorageBytes() throws {
    try withSettings { settings, defaults in
      let legacy = Data("old retained generation".utf8)
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] {
        defaults.set(legacy, forKey: key)
      }
      var incoming = try incomingSource().applying(to: AppSettingsSnapshot(fontSize: 35))
      incoming.theme = .midnight
      incoming.soundVolume = 0.75
      incoming.quickEnd = true
      XCTAssertTrue(settings.apply(incoming))
      XCTAssertEqual(settings.snapshot, incoming)
      let reader = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.snapshot, incoming)
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] {
        XCTAssertEqual(defaults.data(forKey: key), legacy)
      }
    }
  }

  func testTestConfigurationAppliesOnlyOwnedFieldsAndPreservesCompleteSource() throws {
    try withSettings { settings, defaults in
      settings.theme = .midnight
      settings.soundVolume = 0.75
      let rules = try incomingSource().applying(to: InputRules(strictSpace: true, quickEnd: true))
      let configuration = TestConfiguration.words(17, difficulty: .expert, rules: rules)
      XCTAssertTrue(settings.apply(configuration))
      XCTAssertEqual(settings.inputRules, rules)
      XCTAssertEqual(settings.difficulty, .expert)
      XCTAssertEqual(settings.fontSize, 31)
      XCTAssertEqual(settings.soundVolume, 0.75)
      XCTAssertEqual(settings.theme, .midnight)
      XCTAssertEqual(
        AppSettings(defaults: defaults, localBackgroundStore: .inMemory()).inputRules, rules)
    }
  }

  func testTestConfigurationDoesNotReapplyUnownedFontOrAnimationSettings() throws {
    try withSettings { settings, _ in
      let font = settings.practiceFontApplicationRevision
      let animation = settings.animationFrameRateRevision
      XCTAssertTrue(settings.apply(.words(17, rules: try incomingSource().applying(to: InputRules()))))
      XCTAssertEqual(settings.practiceFontApplicationRevision, font)
      XCTAssertEqual(settings.animationFrameRateRevision, animation)
    }
  }

  func testNonLosslessCandidateDoesNotWritePreferencesPublishEventsOrChangeTheOwner() throws {
    try withSettings { settings, defaults in
      let before = settings.snapshot
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      let revision = settings.practiceWrapperRevision
      let fontRevision = settings.practiceFontApplicationRevision
      var incoming = try incomingSource().applying(to: AppSettingsSnapshot(fontSize: 35))
      incoming.installedPracticeFontName = "  Fixture Font  "
      XCTAssertFalse(settings.apply(incoming))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      XCTAssertEqual(settings.practiceWrapperRevision, revision)
      XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision)
      incoming = try incomingSource().applying(to: .init())
      incoming.minimumWpm = 99
      XCTAssertFalse(settings.apply(incoming))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testLoadingRetainsLegacyAndSourceApplicationEventParity() throws {
    try withSettings { settings, defaults in
      let wrapper = settings.practiceWrapperRevision
      let font = settings.practiceFontApplicationRevision
      let animation = settings.animationFrameRateRevision
      defaults.removeObject(forKey: "appSettings.v4")
      defaults.set(try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 31)), forKey: "appSettings.v1")
      let legacy = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      XCTAssertEqual(legacy.practiceWrapperRevision, wrapper)
      XCTAssertEqual(legacy.practiceFontApplicationRevision, font)
      XCTAssertEqual(legacy.animationFrameRateRevision, animation)
    }
  }

  func testLockedSourceApplicationRejectsBothOverloadsWithoutPartialChanges() throws {
    try withSettings { settings, defaults in
      let before = settings.snapshot
      let domain = defaults.dictionaryRepresentation() as NSDictionary
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      XCTAssertFalse(settings.apply(try incomingSource().applying(to: .init(fontSize: 35))))
      XCTAssertFalse(
        settings.apply(.words(17, rules: try incomingSource().applying(to: InputRules()))))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
    }
  }

  func testUnreadableOrMissingLiveSourceCannotBeOverwrittenOrUsedForLegacyFallback() throws {
    for replacement in [
      Data("{\"version\":5}".utf8) as Any, Data([1, 2, 3]) as Any, "wrong type" as Any,
      Optional<Data>.none as Any,
    ] {
      try withSettings { settings, defaults in
        if let data = replacement as? Data {
          defaults.set(data, forKey: "appSettings.v4")
        } else if let text = replacement as? String {
          defaults.set(text, forKey: "appSettings.v4")
        } else {
          defaults.removeObject(forKey: "appSettings.v4")
        }
        let domain = defaults.dictionaryRepresentation() as NSDictionary
        let before = settings.snapshot
        let incoming = try incomingSource().applying(to: AppSettingsSnapshot(fontSize: 35))
        XCTAssertFalse(settings.apply(incoming))
        XCTAssertEqual(settings.snapshot, before)
        let reader = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
        let readerBefore = reader.snapshot
        XCTAssertFalse(reader.apply(incoming))
        XCTAssertEqual(reader.snapshot, readerBefore)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, domain)
      }
    }
  }

  func testNoImplicitAdoptionOrDowngradeAndLegacyApplicationKeepsItsOldPath() throws {
    try withSettings { settings, defaults in
      let before = settings.snapshot
      XCTAssertFalse(settings.apply(AppSettingsSnapshot(fontSize: 42)))
      XCTAssertFalse(settings.apply(TestConfiguration.words(17)))
      XCTAssertEqual(settings.snapshot, before)
      defaults.removeObject(forKey: "appSettings.v4")
      let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 22))
      defaults.set(legacy, forKey: "appSettings.v1")
      let target = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      XCTAssertFalse(target.apply(try incomingSource().applying(to: .init(fontSize: 35))))
      XCTAssertNil(defaults.object(forKey: "appSettings.v4"))
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), legacy)
      XCTAssertTrue(target.apply(AppSettingsSnapshot(fontSize: 42)))
      XCTAssertEqual(target.fontSize, 42)
    }
  }

  func testCanonicalApplicationDoesNotDependOnPreviousErrorHandlingMode() throws {
    try withSettings { settings, _ in
      settings.confidenceMode = .maximum
      let stopped = try incomingSource().applying(to: AppSettingsSnapshot(stopOnErrorMode: .word))
      XCTAssertTrue(settings.apply(stopped))
      XCTAssertEqual(settings.snapshot, stopped)
      let confident = try incomingSource().applying(
        to: AppSettingsSnapshot(confidenceMode: .maximum))
      XCTAssertTrue(settings.apply(confident))
      XCTAssertEqual(settings.snapshot, confident)
    }
  }

  func testSoundConfigurationSeesOnlyCommittedWholeStateAndDoesNotTouchOtherStores() throws {
    try withSettings { _, defaults in
      var incoming = try incomingSource().applying(to: AppSettingsSnapshot(fontSize: 35))
      incoming.playKeyclickSound = true
      incoming.clickSoundStyle = .tink
      defaults.set(Data("selection".utf8), forKey: "activeTestSelection.v1")
      defaults.set(["retained layout"], forKey: "layoutFluidLayouts.v1")
      weak var current: AppSettings?
      var loads = 0
      let sound = TypingFeedbackSound(
        loadSound: { _ in
          loads += 1
          XCTAssertEqual(current?.snapshot, incoming)
          XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(incoming))
          return nil
        }, beep: {})
      let target = AppSettings(
        defaults: defaults, feedbackSound: sound, localBackgroundStore: .inMemory())
      current = target
      // The ordinary initializer owns the layout sidecar's existing normalization.
      let layoutBytes = defaults.object(forKey: "layoutFluidLayouts.v1") as? [String]
      XCTAssertTrue(target.apply(incoming))
      XCTAssertGreaterThan(loads, 0)
      XCTAssertEqual(defaults.data(forKey: "activeTestSelection.v1"), Data("selection".utf8))
      XCTAssertEqual(defaults.object(forKey: "layoutFluidLayouts.v1") as? [String], layoutBytes)
    }
  }
}
