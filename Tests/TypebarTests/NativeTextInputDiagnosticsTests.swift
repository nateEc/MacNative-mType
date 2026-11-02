import XCTest
@testable import Typebar

final class NativeTextInputDiagnosticsTests: XCTestCase {
  func testOnlyAnExplicitlyEnabledInMemoryQAPackageCanRecord() {
    let flag = ["TYPEBAR_QA_NATIVE_INPUT_DIAGNOSTICS": "1"]
    let qa: [String: Any] = [QAStoreMode.inMemoryInfoKey: true]
    XCTAssertFalse(NativeTextInputDiagnostics.isEnabled(info: [:], environment: [:]))
    XCTAssertFalse(NativeTextInputDiagnostics.isEnabled(info: [:], environment: flag))
    XCTAssertFalse(NativeTextInputDiagnostics.isEnabled(info: qa, environment: [:]))
    XCTAssertFalse(NativeTextInputDiagnostics.isEnabled(info: [QAStoreMode.inMemoryInfoKey: "true"], environment: flag))
    XCTAssertTrue(NativeTextInputDiagnostics.isEnabled(info: qa, environment: flag))
  }

  func testDisabledObservationDoesNotConsumeTheFiniteEvidenceBudget() {
    var budget = NativeTextInputDiagnostics.Budget()
    for _ in 0..<100 { XCTAssertFalse(budget.admit(enabled: false)) }
    for _ in 0..<96 { XCTAssertTrue(budget.admit(enabled: true)) }
    XCTAssertFalse(budget.admit(enabled: true))
  }

  func testDeadKeyAndFollowingCommitAreDistinguishableWithoutRecordingText() {
    XCTAssertEqual(NativeTextInputDiagnostics.record(phase: .keyDown, keyCode: 14,
      units: 0, basicUnits: 1, option: true, admitted: true, retired: false, marked: false),
      "phase=keyDown key=14 units=0 basicUnits=1 option=true shift=false command=false control=false admitted=true retired=false marked=false applicationActive=false windowKey=false firstResponder=false contextOwner=-1")
    XCTAssertEqual(NativeTextInputDiagnostics.record(phase: .insert, units: 1,
      admitted: true, retired: false, marked: true),
      "phase=insert key=-1 units=1 basicUnits=-1 option=false shift=false command=false control=false admitted=true retired=false marked=true applicationActive=false windowKey=false firstResponder=false contextOwner=-1")
  }
}
