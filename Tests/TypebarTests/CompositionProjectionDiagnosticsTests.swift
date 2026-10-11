import XCTest
@testable import Typebar

final class CompositionProjectionDiagnosticsTests: XCTestCase {
  func testRequiresBothExplicitQAFlags() {
    XCTAssertFalse(CompositionProjectionDiagnostics.isEnabled(environment: [:]))
    XCTAssertFalse(CompositionProjectionDiagnostics.isEnabled(environment:
      ["TYPEBAR_QA_IN_MEMORY_STORE": "1"]))
    XCTAssertFalse(CompositionProjectionDiagnostics.isEnabled(environment:
      ["TYPEBAR_QA_COMPOSITION_DIAGNOSTICS": "1"]))
    XCTAssertTrue(CompositionProjectionDiagnostics.isEnabled(environment:
      ["TYPEBAR_QA_IN_MEMORY_STORE": "1", "TYPEBAR_QA_COMPOSITION_DIAGNOSTICS": "1"]))
  }

  func testOnlyMarkedMissingExpectedProjectionConsumesBoundedBudget() {
    var budget = CompositionProjectionDiagnostics.Budget()
    for _ in 0..<30 {
      XCTAssertFalse(budget.admit(enabled: false, expected: true, available: false, marked: true))
      XCTAssertFalse(budget.admit(enabled: true, expected: false, available: false, marked: true))
      XCTAssertFalse(budget.admit(enabled: true, expected: true, available: true, marked: true))
      XCTAssertFalse(budget.admit(enabled: true, expected: true, available: false, marked: false))
    }
    for _ in 0..<20 {
      XCTAssertTrue(budget.admit(enabled: true, expected: true, available: false, marked: true))
    }
    XCTAssertFalse(budget.admit(enabled: true, expected: true, available: false, marked: true))
  }

  func testRecordDistinguishesFinishedSessionFromMissingActiveFieldWithoutText() {
    XCTAssertEqual(CompositionProjectionDiagnostics.record(started: true, finished: true,
      fieldAvailable: false),
      "typebar-composition projection=unavailable started=true finished=true fieldAvailable=false\n")
    XCTAssertEqual(CompositionProjectionDiagnostics.record(started: false, finished: false,
      fieldAvailable: true),
      "typebar-composition projection=unavailable started=false finished=false fieldAvailable=true\n")
  }
}
