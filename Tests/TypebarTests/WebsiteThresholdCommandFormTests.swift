import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteThresholdCommandFormTests: XCTestCase {
  func testSingleFlightCapturesInputAndCancellationSuppressesLateSuccess() async throws {
    let form = WebsiteThresholdCommandForm(text: "73tail", target: .minimumWordBurst(.fixed), unit: .cpm)
    var reply: CheckedContinuation<WebsiteThresholdCommandReceipt, Never>?
    defer { reply?.resume(returning: .init(publicationID: UUID(), acceptedSetters: 0, rejectedKeys: [])) }
    var inputs: [String] = [], completions = 0
    let apply: @MainActor (String) async throws -> WebsiteThresholdCommandReceipt = { input in
      inputs.append(input)
      return await withCheckedContinuation { reply = $0 }
    }
    form.submit(apply: apply, completed: { completions += 1 })
    form.text = "99"
    form.submit(apply: apply, completed: { completions += 1 })
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertEqual(inputs, ["73tail"]); XCTAssertTrue(form.isWorking)
    form.cancel()
    let pending = reply; reply = nil
    pending?.resume(returning: .init(publicationID: UUID(), acceptedSetters: 2, rejectedKeys: []))
    for _ in 0..<20 { await Task.yield() }
    XCTAssertFalse(form.isWorking); XCTAssertNil(form.message); XCTAssertEqual(completions, 0)
  }

  func testValidationAndPartialExecutionHaveDifferentDismissalBehavior() async throws {
    let invalid = WebsiteThresholdCommandForm(text: "73tail", target: .minimumWpmCustom, unit: .cpm)
    var calls = 0, completions = 0
    invalid.submit(apply: { _ in calls += 1; throw WebsiteThresholdCommandError.invalidInput }, completed: { completions += 1 })
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(calls, 0); XCTAssertEqual(completions, 0)
    let burst = WebsiteThresholdCommandForm(text: " ", target: .minimumWordBurst(.flex), unit: .cpm)
    burst.submit(apply: { _ in
      calls += 1
      return .init(publicationID: UUID(), acceptedSetters: 1, rejectedKeys: ["minBurstCustomSpeed"])
    }, completed: { completions += 1 })
    while burst.isWorking { await Task.yield() }
    XCTAssertEqual(calls, 1); XCTAssertEqual(completions, 1)
    XCTAssertNotNil(burst.message)
    burst.submit(apply: { _ in throw WebsiteThresholdCommandError.partiallySaved(WebsiteConfigImportWorkflowError.conflict) },
      completed: { completions += 1 })
    while burst.isWorking { await Task.yield() }
    XCTAssertEqual(completions, 1); XCTAssertTrue(burst.message?.contains("已保存") == true)
  }
}
