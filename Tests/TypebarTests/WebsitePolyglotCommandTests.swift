import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsitePolyglotCommandTests: XCTestCase {
  private func render(_ host: NSView) {
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  }
  func testPinnedPolyglotInputCommandHasNativeAction() {
    XCTAssertEqual(CommandPaletteUtilityCatalog.action(for: "setCustomPolyglotCustom"), .editWebsitePolyglot)
    let legacy = CommandPaletteUtilityCatalog.items(randomThemeEnabled: false, authenticated: false)
    XCTAssertFalse(legacy.contains { $0.id == "setCustomPolyglotCustom" })
    let website = CommandPaletteUtilityCatalog.items(randomThemeEnabled: false, authenticated: false,
      websiteProfileActive: true)
    for query in ["customPolyglot", "polyglot", "多语", "setCustomPolyglotCustom"] {
      XCTAssertEqual(CommandPaletteSearch.results(items: website, query: query).map(\.id), ["setCustomPolyglotCustom"])
    }
  }

  func testCommandRendersSavedLanguagesWithoutApplyingOrShowingWindow() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"customPolyglot":["german","spanish"]}"#,
      pointsPerRem: 16, context: .init())
    for dark in [false, true] {
      for available in [false, true] {
        let form = WebsiteConfigPracticeEditForm(draft: draft)
        var calls = 0
        let view = WebsitePolyglotCommandView(form: form, canApply: available,
          apply: { _ in calls += 1; return "unexpected" })
          .frame(width: 540, height: 340)
          .background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 540, height: 340),
          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/typebar-polyglot-command-\(available)-\(dark ? "dark" : "light").png"))
        XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible)
        XCTAssertEqual(form.polyglotLanguages, "german spanish"); XCTAssertEqual(calls, 0)
      }
    }
  }

  func testRemovingCommandCancelsPendingFormAndSuppressesLateSuccess() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    let form = WebsiteConfigPracticeEditForm(draft: draft)
    let host = NSHostingView(rootView: AnyView(WebsitePolyglotCommandView(form: form, canApply: true,
      apply: { _ in "unused" })))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 540, height: 340),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    render(host)
    var reply: CheckedContinuation<String, Never>?
    defer { reply?.resume(returning: "cleanup") }
    form.startPolyglotLanguages { _ in await withCheckedContinuation { reply = $0 } }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertNotNil(reply); XCTAssertTrue(form.isWorking)
    host.rootView = AnyView(EmptyView())
    render(host)
    XCTAssertFalse(form.isWorking)
    let message = form.message
    let pending = reply; reply = nil; pending?.resume(returning: "late success")
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(form.message, message); XCTAssertTrue(message?.contains("已取消") == true)
    XCTAssertFalse(window.isVisible)
  }
}
