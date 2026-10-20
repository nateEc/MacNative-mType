import XCTest
@testable import Typebar

final class WordPracticePersistenceEventTests: XCTestCase {
  private func selection(_ configuration: TestConfiguration, text: String? = nil) -> ActiveTestSelectionDocument {
    .init(preset: .init(configuration: configuration, customText: text),
      testParameterMemory: .init(duration: 30, wordLimit: 17,
        customTextDuration: 45, customTextWordLimit: 9, customTextSectionLimit: 10))
  }

  private func transition(previous: WordPracticeTransition? = nil) throws -> WordPracticeTransition {
    let source = selection(.words(17))
    let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["a|b", "e\u{301}"], selectedTargetCount: 2))
    return try XCTUnwrap(WordPracticeTransition.begin(previous: previous, practice: practice,
      currentPreset: { source.preset }, currentSelection: { _ in source }, selectCustomMode: { true }))
  }

  private var current: ActiveTestSelectionDocument {
    selection(.init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .french,
      customTextCompletion: .sections, customTextSectionLimit: 10,
      customTextOrdering: .shuffled, customTextPipeDelimiter: true), text: "a|b | e\u{301}")
  }

  func testAnExplicitConfigSaveSurvivesAReaderAndLaterAutomaticResets() throws {
    let suite = "typebar.practice-save.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ActiveTestSelectionStore(defaults: defaults)
    var navigation = try transition()
    XCTAssertTrue(navigation.persistSelection(current: current, cause: .automatic, save: store.save))
    XCTAssertEqual(store.load()?.preset.configuration.mode, .words)
    XCTAssertTrue(navigation.persistSelection(current: current, cause: .configurationSave, save: store.save))
    let reader = ActiveTestSelectionStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    XCTAssertEqual(reader.load(), current)
    XCTAssertTrue(navigation.persistSelection(current: current, cause: .automatic, save: store.save))
    XCTAssertEqual(reader.load(), current)
  }

  func testNestedPracticeDoesNotUndoTheLastSuccessfulExplicitSave() throws {
    var first = try transition()
    XCTAssertTrue(first.persistSelection(current: current, cause: .configurationSave, save: { _ in true }))
    let nested = try transition(previous: first)
    XCTAssertEqual(nested.persistedSelection(current: selection(.words(99))), current)
    XCTAssertEqual(nested.returnPreset.configuration.mode, .words)
  }

  func testRejectedWriteDoesNotPromoteTheAttemptedConfiguration() throws {
    var navigation = try transition()
    let original = navigation.persistedSelection(current: current)
    XCTAssertFalse(navigation.persistSelection(current: current, cause: .configurationSave, save: { _ in false }))
    XCTAssertEqual(navigation.persistedSelection(current: current), original)
    XCTAssertTrue(navigation.persistSelection(current: current, cause: .configurationSave, save: { _ in true }))
    let rejected = selection(.timed(seconds: 99))
    XCTAssertFalse(navigation.persistSelection(current: rejected, cause: .configurationSave, save: { _ in false }))
    XCTAssertEqual(navigation.persistedSelection(current: rejected), current)
  }

  func testAnExplicitSaveOfAnUnchangedValueStillWritesCurrentMode() throws {
    var navigation = try transition()
    var written: ActiveTestSelectionDocument?
    XCTAssertTrue(navigation.persistSelection(current: current, cause: .configurationSave, save: { written = $0; return true }))
    XCTAssertEqual(written, current)
  }

  func testAStoredExplicitSelectionAndIndependentPoolCreateTheActualColdSession() throws {
    let suite = "typebar.practice-cold.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = ["a|b", "e\u{301}"]
    let state = CustomTextStateDocument(source: .prepared(source), configuration: current.preset.configuration)
    XCTAssertTrue(CustomTextStateStore(defaults: defaults).save(state))
    var navigation = try transition()
    XCTAssertTrue(navigation.persistSelection(current: current, cause: .configurationSave,
      save: ActiveTestSelectionStore(defaults: defaults).save))
    let reader = try XCTUnwrap(UserDefaults(suiteName: suite))
    let selected = try XCTUnwrap(ActiveTestSelectionStore(defaults: reader).load())
    let restored = CustomTextRestorePolicy.restoration(read: CustomTextStateStore(defaults: reader).read(),
      activePreset: selected.preset, explicitSelectionImport: false)
    let document = try XCTUnwrap(restored.document)
    let candidates = try XCTUnwrap(document.source.preparedSections(matching: document.source.text))
    XCTAssertEqual(candidates.map { Array($0.utf16) }, source.map { Array($0.utf16) })
    XCTAssertEqual(selected.preset.configuration.language, .french)
    var session = TestSessionFactory.make(configuration: selected.preset.configuration,
      customText: document.source.text, preparedCustomSections: candidates)
    let start = Date(timeIntervalSince1970: 1_000)
    session.insertBatch(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.sectionProgress?.completed, 10)
    XCTAssertEqual(Set(session.wordReviews.map { Array($0.target.utf16) }), Set(source.map { Array($0.utf16) }))
    var repeated = session.repeatedAttempt()
    repeated.insertBatch(session.prompt, at: start.addingTimeInterval(1))
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.wordReviews.map { Array($0.target.utf16) }, session.wordReviews.map { Array($0.target.utf16) })
  }
}
