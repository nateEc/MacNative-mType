import XCTest
@testable import Typebar

final class CustomWordDurationSelectionTests: XCTestCase {
  private var dual: TestConfiguration {
    .init(mode: .custom, duration: 3_600, wordLimit: 10_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words)
  }

  func testUnqualifiedDualBoundSurvivesRestartAndEndsAtHourBeforeWordLimit() throws {
    XCTAssertTrue(SettingsJSONConfigurationPolicy.isValid(dual))
    var state = CustomWordDurationSelection()
    state.accept(dual)
    state.reconcile(mode: .custom, completion: .words, wordLimit: 10_000)
    XCTAssertEqual(state.duration(mode: .custom, completion: .words, wordLimit: 10_000), 3_600)
    var session = TestSessionFactory.make(configuration: dual, customText: "amber bay")
    let start = Date(timeIntervalSince1970: 100)
    session.insertBatch("a", at: start)
    session.tick(at: start.addingTimeInterval(3_599))
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(try XCTUnwrap(session.nextExpectedCharacter)),
      at: start.addingTimeInterval(3_599))
    session.tick(at: start.addingTimeInterval(3_600))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertNil(result.configuration.challengeID)
    XCTAssertLessThan(session.completedWordCount, 10_000)
  }

  func testChangingModeCompletionOrWordLimitRetiresBoundWithoutRevivingIt() {
    for mutation in ["mode", "completion", "words"] {
      var state = CustomWordDurationSelection()
      state.accept(dual)
      state.reconcile(mode: mutation == "mode" ? .words : .custom,
        completion: mutation == "completion" ? .time : .words,
        wordLimit: mutation == "words" ? 25 : 10_000)
      state.reconcile(mode: .custom, completion: .words, wordLimit: 10_000)
      XCTAssertNil(state.duration, mutation)
    }
  }

  func testExplicitUnboundedSelectionClearsPreviousTimeoutAndInvalidPairsStayInvalid() {
    var state = CustomWordDurationSelection()
    state.accept(dual)
    var unbounded = dual
    unbounded.duration = nil
    state.accept(unbounded)
    XCTAssertNil(state.duration)
    for invalid in [Double.nan, -1, 60] {
      var configuration = dual
      configuration.duration = invalid
      XCTAssertFalse(SettingsJSONConfigurationPolicy.isValid(configuration))
      state.accept(configuration)
      XCTAssertNil(state.duration)
    }
    var unknown = dual
    unknown.challengeID = "unknown"
    XCTAssertFalse(SettingsJSONConfigurationPolicy.isValid(unknown))
  }

  func testDualBoundSurvivesColdSelectionCodecWithoutChallengeIdentity() throws {
    let document = ActiveTestSelectionDocument(preset: .init(configuration: dual, customText: "amber bay"),
      testParameterMemory: .init(duration: 30, wordLimit: 25, customTextDuration: 30,
        customTextWordLimit: 10_000, customTextSectionLimit: 1))
    let decoded = try JSONDecoder().decode(ActiveTestSelectionDocument.self,
      from: JSONEncoder().encode(document))
    let accepted = try XCTUnwrap(ActiveTestSelectionPolicy.validated(decoded))
    var state = CustomWordDurationSelection()
    state.accept(accepted.preset.configuration)
    state.reconcile(mode: .custom, completion: .words, wordLimit: accepted.testParameterMemory.customTextWordLimit)
    XCTAssertEqual(state.duration, 3_600)
    XCTAssertNil(accepted.preset.configuration.challengeID)
  }
}
