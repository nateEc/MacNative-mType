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
}
