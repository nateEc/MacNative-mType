import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigImportFormTests: XCTestCase {
  private func settle(_ form: WebsiteConfigImportForm) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking)
  }
  func testAcceptedImportFailureReportsSavedConfigurationInsteadOfRollback() async {
    let form = WebsiteConfigImportForm(apply: { _ in
      throw WebsiteConfigSavedPreparationError(underlying: NSError(domain: "owned-reader", code: 1))
    }, cancel: {})
    form.json = "owned JSON"; form.start()
    await settle(form)
    XCTAssertTrue(form.isError)
    XCTAssertTrue(form.message?.contains("设置已保存") == true)
    XCTAssertTrue(form.message?.contains("继续准备") == true)
    form.cancel()
    XCTAssertTrue(form.message?.contains("已保存的配置保留") == true)
    XCTAssertEqual(form.json, "owned JSON")
  }
  func testCancelRetiresLateSuccessAndAllowsRetryWithoutChangingEditor() async throws {
    var pending: CheckedContinuation<String, Never>?
    var inputs: [String?] = [], cancellations = 0
    let form = WebsiteConfigImportForm(apply: { input in
      inputs.append(input)
      if inputs.count == 1 { return await withCheckedContinuation { pending = $0 } }
      return "second applied"
    }, cancel: { cancellations += 1 })
    form.json = "owned JSON"
    form.start(); form.start()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while pending == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertNotNil(pending); XCTAssertEqual(inputs.count, 1); XCTAssertTrue(form.isWorking)
    var returnCalls = 0
    XCTAssertFalse(form.useTypebarSettings { returnCalls += 1 })
    XCTAssertEqual(returnCalls, 0)
    form.cancel()
    XCTAssertEqual(cancellations, 1); XCTAssertFalse(form.isWorking)
    let cancelledMessage = form.message
    pending?.resume(returning: "late applied"); pending = nil
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(form.message, cancelledMessage)
    form.start(restoring: true)
    await settle(form)
    XCTAssertFalse(form.isWorking); XCTAssertFalse(form.isError)
    XCTAssertEqual(form.message, "second applied"); XCTAssertEqual(form.json, "owned JSON")
    XCTAssertNil(inputs.last!)
  }

  func testWorkflowFailureIsActionableAndDoesNotReportSuccess() async {
    let form = WebsiteConfigImportForm(apply: { _ in throw WebsiteConfigImportWorkflowError.typebarBackup }, cancel: {})
    form.start()
    await settle(form)
    XCTAssertTrue(form.isError)
    XCTAssertTrue(form.message?.contains("Typebar 备份") == true)
    XCTAssertTrue(form.message?.contains("导入设置 JSON") == true)
  }

  func testNativePanelRendersWithoutShowingAWindowOrRunningAnImport() throws {
    var calls = 0
    let form = WebsiteConfigImportForm(apply: { _ in calls += 1; return "unexpected" }, cancel: {})
    form.json = "{\n  \"mode\": \"words\",\n  \"words\": 50\n}"
    let host = NSHostingView(rootView: WebsiteConfigImportView(form: form, useTypebarSettings: { calls += 1 })
      .frame(width: 760, height: 600).background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 760, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = host
    defer { window.contentView = nil; window.close() }
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/typebar-website-config-import-panel.png"))
    XCTAssertGreaterThan(png.count, 1000)
    XCTAssertEqual(calls, 0); XCTAssertFalse(window.isVisible)
  }

  func testWindowReturnReportsFailureWithoutClaimingSuccessAndKeepsEditor() {
    let form = WebsiteConfigImportForm(apply: { _ in "not used" }, cancel: {})
    form.json = "owned text"
    XCTAssertFalse(form.useTypebarSettings { throw PracticePageSessionStateError.locked })
    XCTAssertTrue(form.isError); XCTAssertTrue(form.message?.contains("先结束当前练习") == true)
    XCTAssertEqual(form.json, "owned text")
    XCTAssertTrue(form.useTypebarSettings {})
    XCTAssertFalse(form.isError); XCTAssertTrue(form.message?.contains("存档保留") == true)
    XCTAssertEqual(form.json, "owned text")
  }
}
