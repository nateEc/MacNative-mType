import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ResultSheetTerminationTests: XCTestCase {
  private func window() -> NSWindow {
    let value = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    value.isReleasedWhenClosed = false
    return value
  }

  func testResultHostAllowsTerminationAndRestoresBothOriginalPolicies() {
    for original in [false, true] {
      let sheet = window(), host = ResultSheetTerminationView(frame: .zero)
      sheet.preventsApplicationTerminationWhenModal = original
      sheet.contentView = host
      XCTAssertFalse(sheet.preventsApplicationTerminationWhenModal)
      sheet.contentView = nil
      XCTAssertEqual(sheet.preventsApplicationTerminationWhenModal, original)
      host.detach()
      XCTAssertEqual(sheet.preventsApplicationTerminationWhenModal, original)
      sheet.close()
    }
  }

  func testActualSwiftUIBackgroundBridgeAttachesAndRestoresItsWindow() {
    let sheet = window()
    sheet.preventsApplicationTerminationWhenModal = true
    let host = NSHostingView(rootView: Text("Finished result")
      .background(ResultSheetTerminationBridge().frame(width: 0, height: 0)))
    sheet.contentView = host
    host.layoutSubtreeIfNeeded()
    XCTAssertFalse(sheet.preventsApplicationTerminationWhenModal)
    sheet.contentView = nil
    XCTAssertTrue(sheet.preventsApplicationTerminationWhenModal)
    sheet.close()
  }

  func testMovingHostRestoresOldWindowWithoutTouchingOtherLongTestProtection() {
    let first = window(), second = window(), protected = window()
    let registry = LongTestTerminationProtectionRegistry.shared
    first.preventsApplicationTerminationWhenModal = true
    second.preventsApplicationTerminationWhenModal = false
    protected.preventsApplicationTerminationWhenModal = true
    registry.update(window: protected, requiresConfirmation: true)
    defer {
      registry.remove(window: protected)
      first.contentView = nil; second.contentView = nil
      first.close(); second.close(); protected.close()
    }
    let host = ResultSheetTerminationView(frame: .zero)
    first.contentView = host
    XCTAssertFalse(first.preventsApplicationTerminationWhenModal)
    first.contentView = nil
    second.contentView = host
    XCTAssertTrue(first.preventsApplicationTerminationWhenModal)
    XCTAssertFalse(second.preventsApplicationTerminationWhenModal)
    XCTAssertTrue(protected.preventsApplicationTerminationWhenModal)
    XCTAssertTrue(registry.requiresConfirmation)
    second.contentView = nil
    XCTAssertFalse(second.preventsApplicationTerminationWhenModal)
    XCTAssertTrue(registry.requiresConfirmation)
  }

  func testProductionBridgeIsScopedToCompletedResultSheet() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let begin = try XCTUnwrap(source.range(of: ".sheet(item: $completedResult)"))
    let end = try XCTUnwrap(source.range(of: ".alert(item: $terminalNotice)", range: begin.upperBound..<source.endIndex))
    XCTAssertTrue(source[begin.lowerBound..<end.lowerBound].contains("ResultSheetTerminationBridge()"))
    XCTAssertEqual(source.components(separatedBy: "ResultSheetTerminationBridge()").count - 1, 1)
  }
}
