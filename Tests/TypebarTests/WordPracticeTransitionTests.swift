import XCTest
@testable import Typebar

final class WordPracticeTransitionTests: XCTestCase {
  private func practice(_ words: [String] = ["a|b", "e\u{301}"]) throws -> WordPracticeText.SectionedPractice {
    try XCTUnwrap(WordPracticeText.sectionedPractice(segments: words, selectedTargetCount: words.count))
  }

  private func selection(_ preset: SavedTestPreset) -> ActiveTestSelectionDocument {
    .init(preset: preset, testParameterMemory: .init(duration: 30, wordLimit: 17,
      customTextDuration: 45, customTextWordLimit: 9, customTextSectionLimit: 7))
  }

  func testCapturesEverySourceModeBeforeTheSelectionCallbackMutatesIt() throws {
    let configurations: [TestConfiguration] = [.timed(seconds: 30), .words(17),
      .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())]
    for configuration in configurations {
      let source = SavedTestPreset(configuration: configuration,
        quoteID: configuration.mode == .quote ? "source-quote" : nil,
        customText: configuration.mode == .custom ? "source e\u{301}" : nil)
      var current = source
      let transition = try XCTUnwrap(WordPracticeTransition.begin(previous: nil,
        practice: practice(), currentPreset: { current }, currentSelection: selection,
        selectCustomMode: {
          current.configuration.mode = .custom
          current.customText = "temporary"
          return true
        }))
      XCTAssertEqual(current.configuration.mode, .custom)
      XCTAssertEqual(transition.returnPreset.configuration, source.configuration)
      XCTAssertEqual(transition.returnPreset.quoteID, source.quoteID)
      XCTAssertEqual(transition.returnPreset.customText.map { Array($0.utf16) },
        source.customText.map { Array($0.utf16) })
      XCTAssertEqual(transition.returnSelection, selection(source))
    }
  }

  func testRejectedSwitchDoesNotReplaceAnExistingPractice() throws {
    let source = SavedTestPreset(configuration: .words(17))
    let first = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice(),
      currentPreset: { source }, currentSelection: selection, selectCustomMode: { true }))
    let rejected = WordPracticeTransition.begin(previous: first, practice: try practice(["rejected"]),
      currentPreset: { XCTFail("A nested practice must not recapture the source"); return source },
      currentSelection: { _ in XCTFail("A nested practice must retain its source selection"); return self.selection(source) },
      selectCustomMode: { false })
    XCTAssertNil(rejected)
    XCTAssertEqual(first.returnPreset, source)
    XCTAssertEqual(first.preparedPractice.sections.map { Array($0.utf16) },
      try practice().sections.map { Array($0.utf16) })
  }

  func testNestedPracticeKeepsTheOriginalSourceAndReplacesOnlyItsCandidates() throws {
    let source = SavedTestPreset(configuration: .timed(seconds: 30))
    let first = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice(),
      currentPreset: { source }, currentSelection: selection, selectCustomMode: { true }))
    let next = try practice(["next|target"])
    let second = try XCTUnwrap(WordPracticeTransition.begin(previous: first, practice: next,
      currentPreset: { XCTFail("Do not capture the temporary custom mode"); return source },
      currentSelection: { _ in XCTFail("Do not replace parameter memory"); return self.selection(source) },
      selectCustomMode: { true }))
    XCTAssertEqual(second.returnPreset, source)
    XCTAssertEqual(second.returnSelection, first.returnSelection)
    XCTAssertEqual(second.preparedSections(matching: next.text), next.sections)
    XCTAssertNil(second.preparedSections(matching: first.preparedPractice.text))
    let restored = PresetApplicationPolicy.applying(
      current: .init(configuration: .words(5)), preset: second.returnPreset)
    XCTAssertEqual(restored.configuration, source.configuration)
    let session = TestSessionFactory.make(configuration: restored.configuration)
    XCTAssertEqual(session.configuration.mode, .time)
    XCTAssertEqual(session.configuration.duration, 30)
  }

  func testTemporaryPracticeDoesNotOverwriteTheSavedSelectionOrParameterMemory() throws {
    let suite = "typebar.word-practice-return.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: 7, customTextOrdering: .inOrder, customTextPipeDelimiter: true)
    let source = SavedTestPreset(configuration: config, customText: "source e\u{301} | tail")
    let expected = selection(source)
    var current = source
    var memory = expected.testParameterMemory
    let transition = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice(),
      currentPreset: { current }, currentSelection: { preset in
        .init(preset: preset, testParameterMemory: memory)
      }, selectCustomMode: {
        current.customText = "a|b | e\u{301}"
        current.configuration.customTextSectionLimit = 10
        memory = .init(duration: memory.duration, wordLimit: memory.wordLimit,
          customTextDuration: memory.customTextDuration, customTextWordLimit: memory.customTextWordLimit,
          customTextSectionLimit: 10)
        return true
      }))
    let temporary = ActiveTestSelectionDocument(preset: current, testParameterMemory: memory)
    XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(transition.persistedSelection(current: temporary)))
    let reader = ActiveTestSelectionStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    let loaded = try XCTUnwrap(reader.load())
    XCTAssertEqual(loaded, expected)
    XCTAssertEqual(loaded.preset.customText.map { Array($0.utf16) }, source.customText.map { Array($0.utf16) })
  }

  func testPreparedCandidateMatchingUsesExactSpellingWithoutChangingTheReturnSelection() throws {
    let source = SavedTestPreset(configuration: .words(17))
    let transition = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice(),
      currentPreset: { source }, currentSelection: selection, selectCustomMode: { true }))
    let text = try practice().text
    XCTAssertNotNil(transition.preparedSections(matching: text))
    XCTAssertNil(transition.preparedSections(matching: text.precomposedStringWithCanonicalMapping))
    XCTAssertEqual(transition.returnPreset, source)
    XCTAssertEqual(transition.returnSelection, selection(source))
  }

  func testEndingTemporaryNavigationLetsAnExplicitNewSourcePersist() throws {
    let original = SavedTestPreset(configuration: .words(17))
    var temporary = WordPracticeTransition.begin(previous: nil, practice: try practice(),
      currentPreset: { original }, currentSelection: selection, selectCustomMode: { true })
    let replacement = selection(.init(configuration: .timed(seconds: 45)))
    XCTAssertEqual(temporary?.persistedSelection(current: replacement), selection(original))
    temporary = nil
    let selected = temporary?.persistedSelection(current: replacement) ?? replacement
    XCTAssertEqual(selected, replacement)
  }
}
