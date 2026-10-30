import XCTest
@testable import Typebar

final class PracticeRestartInstructionTests: XCTestCase {
  func testReadyInstructionsKeepAllExistingShortcutsAndLongTestProtection() {
    let ordinary: [QuickRestartKey: String] = [.off: "可使用 ⌘R 重新开始", .escape: "Esc 可重新开始",
      .tab: "Tab 可重新开始", .enter: "Enter 可重新开始"]
    let protected: [QuickRestartKey: String] = [.off: "可用 ⌘R 重开", .escape: "Shift+Esc 可重新开始",
      .tab: "Shift+Tab 可重新开始", .enter: "⌘R 可重开"]
    for key in QuickRestartKey.allCases {
      XCTAssertEqual(PracticeRestartInstruction.text(hasStarted: false, key: key, requiresProtection: false),
        "按任意键开始，" + ordinary[key]!)
      XCTAssertEqual(PracticeRestartInstruction.text(hasStarted: false, key: key, requiresProtection: true),
        "按任意键开始，" + protected[key]! + "；双击 Shift+Enter 中止并显示结果")
    }
  }

  func testStartedInstructionsDescribePracticeWithoutChangingRestartOrBailoutShortcuts() {
    for key in QuickRestartKey.allCases {
      for protection in [false, true] {
        let ready = PracticeRestartInstruction.text(hasStarted: false, key: key, requiresProtection: protection)
        let active = PracticeRestartInstruction.text(hasStarted: true, key: key, requiresProtection: protection)
        XCTAssertTrue(active.hasPrefix("正在练习，"), active)
        XCTAssertFalse(active.contains("按任意键开始"), active)
        XCTAssertEqual(active.split(separator: "，", maxSplits: 1).last,
          ready.split(separator: "，", maxSplits: 1).last)
      }
    }
  }

  func testRealSessionFirstInsertionAndFreshAttemptChooseTheirOwnInstructionPhase() {
    let configuration = TestConfiguration.timed(seconds: 30)
    var session = TypingSession(configuration: configuration, prompt: "quiet river")
    func instruction(_ value: TypingSession) -> String {
      PracticeRestartInstruction.text(hasStarted: value.hasStarted, key: .off, requiresProtection: false)
    }
    XCTAssertTrue(instruction(session).hasPrefix("按任意键开始"))
    session.insert("q", at: Date(timeIntervalSinceReferenceDate: 10_000))
    XCTAssertTrue(session.hasStarted)
    XCTAssertTrue(instruction(session).hasPrefix("正在练习"))
    let next = TypingSession(configuration: configuration, prompt: "quiet river")
    XCTAssertTrue(instruction(next).hasPrefix("按任意键开始"))
  }
}
