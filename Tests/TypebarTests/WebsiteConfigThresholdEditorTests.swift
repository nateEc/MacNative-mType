import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigThresholdEditorTests: XCTestCase {
  func testNativeNumericInputPreservesZeroAndRejectsInvalidRangesWithoutChangingModeImplicitly() {
    XCTAssertEqual(WebsiteConfigThresholdField.speed.valueEdit(" 0\n"), .speedValue(0))
    XCTAssertEqual(WebsiteConfigThresholdField.accuracy.valueEdit("91.5"), .accuracyValue(91.5))
    XCTAssertEqual(WebsiteConfigThresholdField.burst.valueEdit("83.5"), .burstValue(83.5))
    for field in WebsiteConfigThresholdField.allCases {
      for invalid in ["", "-1", "nan", "inf", "1e400", "73abc"] { XCTAssertNil(field.valueEdit(invalid)) }
    }
    XCTAssertNil(WebsiteConfigThresholdField.accuracy.valueEdit("100.01"))
    XCTAssertEqual(WebsiteConfigThresholdField.accuracy.valueEdit("100"), .accuracyValue(100))
    XCTAssertEqual(WebsiteConfigThresholdField.speed.modeEdit("custom"), .speedMode(.custom))
    XCTAssertEqual(WebsiteConfigThresholdField.burst.modeEdit("flex"), .burstMode(.flex))
    XCTAssertNil(WebsiteConfigThresholdField.speed.modeEdit("fixed"))
  }

  func testThresholdActionsUseSharedFormSingleFlightAndSavingFeedback() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4}"#,
      pointsPerRem: 16, context: .init())
    let form = WebsiteConfigPracticeEditForm(draft: draft)
    var reply: CheckedContinuation<String, Never>?, edits: [WebsiteConfigPracticeEdit] = []
    form.start(.threshold(.speedValue(0))) { edit in
      edits.append(edit); return await withCheckedContinuation { reply = $0 }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
    defer { reply?.resume(returning: "cancelled"); form.cancel() }
    XCTAssertEqual(form.activityText, "正在保存阈值…")
    form.start(.threshold(.burstMode(.fixed))) { edit in edits.append(edit); return "unexpected" }
    XCTAssertEqual(edits, [.threshold(.speedValue(0))])
    let complete = try XCTUnwrap(reply); reply = nil; complete.resume(returning: "saved without restarting")
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking)
    XCTAssertEqual(form.message, "saved without restarting")
    XCTAssertFalse(WebsiteConfigPracticeEdit.threshold(.speedValue(0)).dispatchesRestartAfterRejection)
  }

  func testThresholdRowsRenderAtCompactAndWideWidthsWithoutOpeningWindowOrApplyingValues() throws {
    var source = PracticeThresholdConfiguration()
    try source.apply(.minimumWpm(mode: .custom, customValue: 0))
    try source.apply(.minimumAccuracy(mode: .off, customValue: 91.5))
    try source.apply(.minimumWordBurst(mode: .flex, customValue: 83.5))
    for (width, dark) in [(420, false), (640, true)] {
      var calls = 0
      let view = WebsiteConfigThresholdEditor(configuration: source, canEdit: true, apply: { _ in calls += 1 })
        .padding(20).frame(width: CGFloat(width), height: 400, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: CGFloat(width), height: 400),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      defer { window.contentView = nil; window.close() }
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: "/tmp/typebar-threshold-editor-\(width)-\(dark ? "dark" : "light").png"))
      XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
    }
  }
}
