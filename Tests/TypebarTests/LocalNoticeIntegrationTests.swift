import Foundation
import XCTest
@testable import Typebar

final class LocalNoticeIntegrationTests: XCTestCase {
  func testNativeSessionNotificationHistoryAndLiveOverlayAreConnected() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("LocalNoticeStack("), "Session notifications must be visible, not an unused model")
    XCTAssertTrue(app.contains("LocalNoticeHistoryView("), "History must have a real native entry point")
    XCTAssertTrue(app.contains("LocalNoticeClipboard.copyText("), "Actual result clipboard outcomes must publish notices")
  }

  func testConfigurationShareAndKnownHTMLMessagesHaveProductionNoticeEntries() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let share = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TestConfigurationShare.swift"), encoding: .utf8)
    let views = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/LocalNoticeViews.swift"), encoding: .utf8)
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(share.contains("TestConfigurationShareActions.apply("), "Import feedback must follow the actual application outcome")
    XCTAssertTrue(views.contains("LocalNoticeMessageView("), "Both live and historical known HTML messages need native presentation")
    XCTAssertTrue(app.contains("reportFunboxConfigurationConflict("), "Funbox rejection must remain visible in session history")
  }

  func testPresetReturnStateIsRetainedUntilRejectionPreflightFinishes() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "private func apply(\n"))
    let end = try XCTUnwrap(source.range(of: "private func restoreActiveTestSelection", range: start.upperBound..<source.endIndex))
    let body = String(source[start.lowerBound..<end.lowerBound])
    let lastRejection = try XCTUnwrap(body.range(of: "return false", options: .backwards))
    let clear = try XCTUnwrap(body.range(of: "practiceReturnPreset = nil"))
    XCTAssertGreaterThan(clear.lowerBound, lastRejection.upperBound,
      "Static ordering guard only: rejected imports must not retire the practice return selection")
  }
}
