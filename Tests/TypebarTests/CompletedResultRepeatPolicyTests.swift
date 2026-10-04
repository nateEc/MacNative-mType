import XCTest
@testable import Typebar

final class CompletedResultRepeatPolicyTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 400)

  private func zenResult(admission: Bool?) throws -> CompletedTestResult {
    var configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init())
    configuration.zenUsesSourceInputAdmission = admission
    var session = TypingSession(configuration: configuration, prompt: "")
    session.insertBatch("hello world", at: start)
    session.finishZen(at: start.addingTimeInterval(4))
    return try XCTUnwrap(session.result())
  }

  private func payloadWithoutGeneratedID(_ result: CompletedTestResult) throws -> Data {
    var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    // result() creates a UUID on each projection, even without session changes.
    payload.removeValue(forKey: "id")
    return try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
  }

  func testZenButtonShowsNoticeWithoutClearingTheFinishedResultOrStartingAnAttempt() throws {
    let original = try zenResult(admission: true)
    var visibleResult: CompletedTestResult? = original
    var attempts = 0
    var notices: [String] = []
    CompletedResultRepeatPolicy.perform(mode: original.configuration.mode, origin: .button,
      showNotice: { notices.append($0) }, repeatAttempt: {
        visibleResult = nil
        attempts += 1
      })
    XCTAssertEqual(visibleResult, original)
    XCTAssertEqual(attempts, 0)
    XCTAssertEqual(notices, ["禅模式的结果按钮不支持重复测试。"])
  }

  func testZenCommandStillDispatchesExactlyOneRepeatWithoutNotice() throws {
    let result = try zenResult(admission: true)
    var attempts = 0
    var notices: [String] = []
    CompletedResultRepeatPolicy.perform(mode: result.configuration.mode, origin: .command,
      showNotice: { notices.append($0) }, repeatAttempt: { attempts += 1 })
    XCTAssertEqual(attempts, 1)
    XCTAssertTrue(notices.isEmpty)
  }

  func testAllOtherNativeModesRepeatFromBothEntrypoints() {
    for mode in TestMode.allCases where mode != .zen {
      for origin in CompletedResultRepeatOrigin.allCases {
        var attempts = 0
        var notices: [String] = []
        CompletedResultRepeatPolicy.perform(mode: mode, origin: origin,
          showNotice: { notices.append($0) }, repeatAttempt: { attempts += 1 })
        XCTAssertEqual(attempts, 1, "\(mode) / \(origin)")
        XCTAssertTrue(notices.isEmpty, "\(mode) / \(origin)")
      }
    }
  }

  func testLegacyAndExplicitFalseZenResultsHaveTheSameButtonRestriction() throws {
    for admission: Bool? in [nil, false, true] {
      let result = try zenResult(admission: admission)
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let encoded = try encoder.encode(result)
      var attempts = 0
      var notices: [String] = []
      CompletedResultRepeatPolicy.perform(mode: result.configuration.mode, origin: .button,
        showNotice: { notices.append($0) }, repeatAttempt: { attempts += 1 })
      XCTAssertEqual(attempts, 0)
      XCTAssertEqual(notices.count, 1)
      XCTAssertEqual(try encoder.encode(result), encoded)
      XCTAssertEqual(result.configuration.zenUsesSourceInputAdmission, admission)
    }
  }

  func testRepeatedButtonActivationNeverStartsOrMutatesAnAttempt() throws {
    let result = try zenResult(admission: true)
    var attempts = 0
    var notices: [String] = []
    for _ in 0..<3 {
      CompletedResultRepeatPolicy.perform(mode: result.configuration.mode, origin: .button,
        showNotice: { notices.append($0) }, repeatAttempt: { attempts += 1 })
    }
    XCTAssertEqual(attempts, 0)
    XCTAssertEqual(notices, Array(repeating: "禅模式的结果按钮不支持重复测试。", count: 3))
  }

  func testCommandAfterBlockedButtonRemainsExecutableAndKeepsLegacyConfiguration() throws {
    for admission: Bool? in [nil, false, true] {
      let result = try zenResult(admission: admission)
      var attempts = 0
      var notices: [String] = []
      for origin in [CompletedResultRepeatOrigin.button, .command] {
        CompletedResultRepeatPolicy.perform(mode: result.configuration.mode, origin: origin,
          showNotice: { notices.append($0) }, repeatAttempt: { attempts += 1 })
      }
      XCTAssertEqual(attempts, 1)
      XCTAssertEqual(notices.count, 1)
      XCTAssertEqual(result.configuration.zenUsesSourceInputAdmission, admission)
    }
  }

  func testRepeatCommandRemainsInTheCatalogWithoutPracticeOrCopyableWords() {
    let items = CompletedResultCommandCatalog.items(availability: .init(
      hasCopyableWords: false, hasWordHistory: false, hasMissedWordPractice: false,
      hasSlowWordPractice: false, hasCombinedPractice: false, hasConfigurablePractice: false))
    XCTAssertEqual(items.map(\.id), ["result.next", "result.repeat", "result.copyImage", "result.saveImage"])
    XCTAssertEqual(CompletedResultCommandCatalog.action(for: "result.repeat"), .repeatTest)
  }

  func testZenCommandCanCallTheActualEngineRepeatWithoutUpgradingOldInputRules() throws {
    for admission: Bool? in [nil, false, true] {
      var configuration = TestConfiguration(mode: .zen, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init())
      configuration.zenUsesSourceInputAdmission = admission
      var original = TypingSession(configuration: configuration, prompt: "")
      original.insertBatch("hello world", at: start)
      original.finishZen(at: start.addingTimeInterval(4))
      let savedResult = try XCTUnwrap(original.result())
      var repeated: TypingSession?
      CompletedResultRepeatPolicy.perform(mode: savedResult.configuration.mode, origin: .command,
        showNotice: { _ in XCTFail("Zen repeat command must not be blocked") },
        repeatAttempt: { repeated = original.repeatedAttempt() })
      let next = try XCTUnwrap(repeated)
      XCTAssertEqual(next.configuration, original.configuration)
      XCTAssertEqual(next.typed, "")
      XCTAssertEqual(next.prompt, "")
      XCTAssertFalse(next.hasStarted)
      XCTAssertEqual(try payloadWithoutGeneratedID(XCTUnwrap(original.result())),
        try payloadWithoutGeneratedID(savedResult))
    }
  }
}
