import XCTest
@testable import Typebar

final class ChallengeSetupSelectionTests: XCTestCase {
  private let selection = ChallengeSetupSelectionPolicy.Selection(language: .spanish,
    englishVariant: .british, mixedLanguageComponents: [.spanish, .french],
    contentOptions: .init(includePunctuation: true, includeNumbers: true))

  private func template(_ id: String) throws -> TestConfiguration {
    try XCTUnwrap(TypebarChallengeLibrary.challenge(id: id)).preset.configuration.with(challengeID: id)
  }

  func testOrdinaryChallengePreservesUnownedSelection() throws {
    let original = try template("thumb-hour")
    let resolved = ChallengeSetupSelectionPolicy.applying(selection, to: original)
    XCTAssertEqual(resolved.language, selection.language)
    XCTAssertEqual(resolved.englishVariant, selection.englishVariant)
    XCTAssertEqual(resolved.mixedLanguageComponents, selection.mixedLanguageComponents)
    XCTAssertEqual(resolved.contentOptions, selection.contentOptions)
    var restored = resolved
    restored.language = original.language
    restored.englishVariant = original.englishVariant
    restored.mixedLanguageComponents = original.mixedLanguageComponents
    restored.contentOptions = original.contentOptions
    XCTAssertEqual(restored, original)
  }

  func testEnglishMasterOwnsItsLanguageAndContentButNotSpellingPreference() throws {
    var current = selection
    current.contentOptions = .init()
    let resolved = ChallengeSetupSelectionPolicy.applying(current,
      to: try template("english-ten-thousand-hour"))
    XCTAssertEqual(resolved.language, .english10k)
    XCTAssertTrue(resolved.contentOptions.includePunctuation)
    XCTAssertTrue(resolved.contentOptions.includeNumbers)
    XCTAssertEqual(resolved.englishVariant, .british)
  }

  func testAsciiFunboxStillForcesBothContentOptionsOff() throws {
    let resolved = ChallengeSetupSelectionPolicy.applying(selection, to: try template("ascii-hour"))
    XCTAssertEqual(resolved.language, .spanish)
    XCTAssertFalse(resolved.contentOptions.includePunctuation)
    XCTAssertFalse(resolved.contentOptions.includeNumbers)
  }

  func testOrdinaryPresetAndUnknownChallengeAreNotTreatedAsLibrarySetup() {
    for configuration in [TestConfiguration.words(3), .words(3).with(challengeID: "unknown")] {
      XCTAssertEqual(ChallengeSetupSelectionPolicy.applying(selection, to: configuration), configuration)
    }
  }

  func testEveryNativeChallengeKeepsMixedLanguageSelectionUnlessItOwnsLanguage() {
    var current = selection
    current.language = .mixedLanguages
    for challenge in TypebarChallengeLibrary.all {
      let template = challenge.preset.configuration.with(challengeID: challenge.id)
      let resolved = ChallengeSetupSelectionPolicy.applying(current, to: template)
      XCTAssertEqual(resolved.language,
        challenge.id == "english-ten-thousand-hour" ? .english10k : .mixedLanguages, challenge.id)
      XCTAssertEqual(resolved.mixedLanguageComponents, [.spanish, .french], challenge.id)
      XCTAssertEqual(resolved.rules, template.rules, challenge.id)
      XCTAssertEqual(resolved.challengeID, challenge.id)
      XCTAssertEqual(resolved.difficulty, template.difficulty, challenge.id)
    }
  }

  @MainActor
  func testResolvedSetupReachesSettingsAndActualSessionWithoutChangingTemplate() throws {
    let suite = "typebar.challenge-selection.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    XCTAssertTrue(settings.apply(.init(strictSpace: true, minimumWpm: 37)))
    let originalRules = settings.inputRules
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
    XCTAssertNil(challenge.preset.configuration.challengeID)
    let original = challenge.preset.configuration
    let resolved = ChallengeSetupSelectionPolicy.applying(selection, for: challenge)
    var preset = challenge.preset
    preset.configuration = original.with(challengeID: challenge.id)
    XCTAssertTrue(PresetSettingsApplication.commit(original: preset, resolved: preset,
      configuration: resolved, to: settings, appliesGlobalSettings: true))
    XCTAssertEqual(resolved.challengeID, challenge.id)
    XCTAssertEqual(settings.inputRules, originalRules)
    XCTAssertEqual(settings.englishVariant, .british)
    let sessionConfiguration = ChallengeInputRulePolicy.applying(settings.inputRules, to: resolved)
    var session = TestSessionFactory.make(configuration: sessionConfiguration)
    XCTAssertEqual(session.configuration.rules, originalRules)
    XCTAssertEqual(session.configuration.language, .spanish)
    XCTAssertEqual(session.configuration.contentOptions, selection.contentOptions)
    session.insertBatch(session.prompt, at: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(session.configuration.challengeID, "thumb-hour")
    XCTAssertEqual(challenge.preset.configuration, original)
    let rebuilt = ChallengeSetupSelectionPolicy.applying(.init(configuration: resolved), for: challenge)
    XCTAssertEqual(rebuilt, resolved)
  }

  func testSavedSelectionRestorationUsesCapturedFieldsRatherThanCurrentDefaults() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
    var captured = ChallengeSetupSelectionPolicy.applying(selection, for: challenge)
    captured.language = .french
    captured.contentOptions = .init(includePunctuation: false, includeNumbers: true)
    let restored = ChallengeSetupSelectionPolicy.applying(.init(configuration: captured), for: challenge)
    XCTAssertEqual(restored.language, .french)
    XCTAssertEqual(restored.contentOptions, captured.contentOptions)
    XCTAssertEqual(restored.challengeID, challenge.id)
  }

  func testFreshSetupClearsPolyglotButRestorationKeepsCapturedBaseLanguage() throws {
    var current = selection
    current.language = .mixedLanguages
    current.polyglotReturnLanguage = .french
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "thumb-hour"))
    let fresh = ChallengeSetupSelectionPolicy.applying(current, for: challenge, clearingPolyglot: true)
    XCTAssertEqual(fresh.language, .french)
    XCTAssertNil(fresh.polyglotBaseLanguage)
    XCTAssertEqual(fresh.mixedLanguageComponents, current.mixedLanguageComponents)
    let restored = ChallengeSetupSelectionPolicy.applying(current, for: challenge)
    XCTAssertEqual(restored.language, .mixedLanguages)
    XCTAssertEqual(restored.polyglotBaseLanguage, .french)
    XCTAssertEqual(ChallengeSetupSelectionPolicy.Selection(configuration: restored).polyglotReturnLanguage, .french)
  }

  func testEnglishMasterStillOverridesFreshPolyglotLanguage() throws {
    var current = selection
    current.language = .mixedLanguages
    current.polyglotReturnLanguage = .french
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "english-ten-thousand-hour"))
    let resolved = ChallengeSetupSelectionPolicy.applying(current, for: challenge, clearingPolyglot: true)
    XCTAssertEqual(resolved.language, .english10k)
    XCTAssertNil(resolved.polyglotBaseLanguage)
    XCTAssertEqual(resolved.contentOptions, .init(includePunctuation: true, includeNumbers: true))
  }
}
