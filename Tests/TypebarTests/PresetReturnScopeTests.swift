import XCTest
@testable import Typebar

final class PresetReturnScopeTests: XCTestCase {
  private func richConfiguration() -> TestConfiguration {
    var configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: 5,
      difficulty: .normal, rules: .init(), language: .mixedLanguages,
      customTextCompletion: .words, customTextOrdering: .random, customTextPipeDelimiter: false,
      polyglotBaseLanguage: .german)
    configuration.polyglotUsesPrimaryDirection = true
    configuration.polyglotUsesPrimaryCodeInput = true
    configuration.polyglotUsesPrimaryInputNormalization = true
    configuration.dockerfileUsesLiteralIndentation = false
    configuration.zenUsesSourceInputAdmission = true
    return configuration
  }

  private var memory: TypebarTestParameterMemory {
    .init(duration: 60, wordLimit: 45, customTextDuration: 20, customTextWordLimit: 5, customTextSectionLimit: 7)
  }

  private func transition(from preset: SavedTestPreset) throws -> WordPracticeTransition {
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["practice"], selectedTargetCount: 1))
    return try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
      currentPreset: { preset }, currentSelection: {
        .init(preset: $0, testParameterMemory: self.memory)
      }, selectCustomMode: { true }))
  }

  func testPartialAppearancePreservesUnselectedConfigurationMetadata() {
    let configuration = richConfiguration()
    var appearance = AppSettingsSnapshot()
    appearance.fontSize = 40
    let applied = PresetApplicationPolicy.applying(
      current: .init(configuration: configuration, customText: "source"),
      preset: .init(configuration: .words(1), settingsSnapshot: appearance, settingGroups: [.appearance]))
    XCTAssertEqual(applied.configuration, configuration)
    XCTAssertEqual(applied.customText, "source")
    XCTAssertEqual(applied.settingsSnapshot?.fontSize, 40)
  }

  func testPartialTestCopiesSourceDelimiterAndGenerationProvenance() {
    let configuration = richConfiguration()
    let applied = PresetApplicationPolicy.applying(current: .init(configuration: .words(25)),
      preset: .init(configuration: configuration, customText: "source", settingGroups: [.test]))
    XCTAssertEqual(applied.configuration, configuration)
    XCTAssertEqual(applied.customText, "source")
  }

  func testSelectedTestGroupCanExplicitlyClearOldProvenanceAndDelimiter() {
    let source = TestConfiguration.words(25)
    let applied = PresetApplicationPolicy.applying(
      current: .init(configuration: richConfiguration(), customText: "old"),
      preset: .init(configuration: source, settingGroups: [.test]))
    XCTAssertEqual(applied.configuration, source)
    XCTAssertNil(applied.customText)
    XCTAssertNil(applied.configuration.customTextPipeDelimiter)
    XCTAssertNil(applied.configuration.polyglotUsesPrimaryDirection)
    XCTAssertNil(applied.configuration.dockerfileUsesLiteralIndentation)
  }

  func testAutomaticReturnRestoresOnlyModeAndContentOptionsWhileKeepingCurrentSettings() throws {
    var originalConfig = TestConfiguration.words(17)
    originalConfig.contentOptions.includePunctuation = true
    var originalSettings = AppSettingsSnapshot()
    originalSettings.fontSize = 28
    originalSettings.soundVolume = 0.2
    let original = SavedTestPreset(configuration: originalConfig, activeResultTags: ["before"],
      settingsSnapshot: originalSettings)
    let navigation = try transition(from: original)
    var currentConfig = richConfiguration()
    currentConfig.difficulty = .expert
    currentConfig.rules.strictSpace = true
    currentConfig.contentOptions.includeNumbers = true
    var currentSettings = AppSettingsSnapshot()
    currentSettings.fontSize = 42
    currentSettings.soundVolume = 0.8
    let current = SavedTestPreset(configuration: currentConfig, customText: "practice",
      activeResultTags: ["latest"], settingsSnapshot: currentSettings)
    let returned = navigation.returningPreset(current: current, parameterMemory: memory)
    var expected = currentConfig
    expected.mode = .words
    expected.duration = nil
    expected.wordLimit = 45
    expected.contentOptions = originalConfig.contentOptions
    XCTAssertEqual(returned.configuration, expected)
    XCTAssertNil(returned.customText)
    XCTAssertEqual(returned.activeResultTags, ["latest"])
    XCTAssertEqual(returned.settingsSnapshot?.fontSize, 42)
    XCTAssertEqual(returned.settingsSnapshot?.soundVolume, 0.8)
    let session = TestSessionFactory.make(configuration: returned.configuration)
    XCTAssertEqual(session.configuration.wordLimit, 45)
    XCTAssertEqual(session.configuration.language, .mixedLanguages)
    XCTAssertTrue(session.configuration.rules.strictSpace)
  }

  func testQuoteReturnKeepsCurrentLanguageAndQuoteSelection() throws {
    let original = SavedTestPreset(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), quoteID: "old")
    let navigation = try transition(from: original)
    let current = SavedTestPreset(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .spanish), customText: "practice")
    let returned = navigation.returningPreset(current: current, parameterMemory: memory, quoteID: "current")
    XCTAssertEqual(returned.configuration.mode, .quote)
    XCTAssertEqual(returned.configuration.language, .spanish)
    XCTAssertEqual(returned.quoteID, "current")
    XCTAssertNil(returned.customText)
    XCTAssertNil(returned.configuration.duration)
    XCTAssertNil(returned.configuration.wordLimit)
  }

  func testTimeReturnUsesCurrentParameterMemoryIncludingInfiniteTime() throws {
    let navigation = try transition(from: .init(configuration: .timed(seconds: 15)))
    let current = SavedTestPreset(configuration: richConfiguration(), customText: "practice")
    for duration in [0, 60] {
      let parameters = TypebarTestParameterMemory(duration: duration, wordLimit: 45,
        customTextDuration: 20, customTextWordLimit: 5, customTextSectionLimit: 7)
      let returned = navigation.returningPreset(current: current, parameterMemory: parameters)
      XCTAssertEqual(returned.configuration.mode, .time)
      XCTAssertEqual(returned.configuration.duration, TimeInterval(duration))
      XCTAssertNil(returned.configuration.wordLimit)
      XCTAssertEqual(returned.configuration.language, current.configuration.language)
      XCTAssertEqual(returned.configuration.polyglotUsesPrimaryInputNormalization,
        current.configuration.polyglotUsesPrimaryInputNormalization)
      XCTAssertEqual(returned.configuration.isInfinite, duration == 0)
    }
  }

  func testReturningCustomSourceRestoresItsLimitButNotItsOldOrdering() throws {
    let captured = CustomTextStateDocument(source: .prepared(["a|b", "e\u{301}"]), configuration:
      .init(mode: .custom, duration: 30, wordLimit: nil, difficulty: .normal, rules: .init(),
        customTextCompletion: .time, customTextOrdering: .random, customTextPipeDelimiter: true))
    let latest = CustomTextStateDocument(source: .prepared(["practice"]), configuration:
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        customTextCompletion: .sections, customTextSectionLimit: 10,
        customTextOrdering: .shuffled, customTextPipeDelimiter: false))
    let result = try XCTUnwrap(CustomTextRestorePolicy.returningSource(captured: captured, latest: { latest }))
    XCTAssertEqual(result.completion, .time)
    XCTAssertEqual(result.duration, 30)
    XCTAssertEqual(result.pipeDelimiter, true)
    XCTAssertEqual(result.ordering, .shuffled)
    XCTAssertEqual(result.source.preparedSections(matching: captured.source.text)?.map { Array($0.utf16) },
      [Array("a|b".utf16), Array("e\u{301}".utf16)])
  }

  func testRejectedReturnAdmissionDoesNotConsumeTheSourceSnapshots() throws {
    let navigation = try transition(from: .init(configuration: .words(17)))
    let current = SavedTestPreset(configuration: richConfiguration(), customText: "practice")
    let first = navigation.returningPreset(current: current, parameterMemory: memory)
    // Selecting the return projection is read-only; a rejected UI apply can
    // retry using the same source and prepared candidates.
    let second = navigation.returningPreset(current: current, parameterMemory: memory)
    XCTAssertEqual(first, second)
    XCTAssertEqual(navigation.returnPreset.configuration.mode, .words)
    XCTAssertNotNil(navigation.preparedSections(matching: navigation.preparedPractice.text))
  }
}
