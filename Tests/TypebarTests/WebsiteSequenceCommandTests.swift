import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteSequenceCommandTests: XCTestCase {
  private func render(_ host: NSView) {
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  }
  func testPinnedLayoutfluidInputCommandHasNativeAction() {
    XCTAssertEqual(CommandPaletteUtilityCatalog.action(for: "setCustomLayoutfluidCustom"), .editWebsiteLayoutfluid)
    let legacy = CommandPaletteUtilityCatalog.items(randomThemeEnabled: false, authenticated: false)
    XCTAssertFalse(legacy.contains { $0.id == "setCustomLayoutfluidCustom" })
    let website = CommandPaletteUtilityCatalog.items(randomThemeEnabled: false, authenticated: false,
      websiteProfileActive: true)
    for query in ["customLayoutfluid", "layoutfluid", "流动布局", "setCustomLayoutfluidCustom"] {
      XCTAssertEqual(CommandPaletteSearch.results(items: website, query: query).map(\.id), ["setCustomLayoutfluidCustom"])
    }
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

  func testCommandsRenderSavedSequencesWithoutApplyingOrShowingWindow() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"customPolyglot":["german","spanish"],"customLayoutfluid":["colemak","qwerty"]}"#,
      pointsPerRem: 16, context: .init())
    for kind in WebsiteSequenceCommandKind.allCases {
      try assertRendering(draft: draft, kind: kind)
    }
  }
  private func assertRendering(draft: WebsiteConfigNativeDraft, kind: WebsiteSequenceCommandKind) throws {
    for dark in [false, true] {
      for available in [false, true] {
        let form = WebsiteConfigPracticeEditForm(draft: draft)
        var calls = 0
        let view = WebsiteSequenceCommandView(form: form, kind: kind, canApply: available,
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
        try png.write(to: URL(fileURLWithPath: "/tmp/\(kind.accessibilityPrefix)-\(available)-\(dark ? "dark" : "light").png"))
        XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible)
        XCTAssertEqual(form.polyglotLanguages, "german spanish"); XCTAssertEqual(calls, 0)
        XCTAssertEqual(form.layoutFluidLayouts, "colemak qwerty")
      }
    }
  }

  func testCommandsSubmitOnlyTheirOwnSequence() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    for kind in WebsiteSequenceCommandKind.allCases {
      let form = WebsiteConfigPracticeEditForm(draft: draft)
      form.polyglotLanguages = "german spanish"
      form.layoutFluidLayouts = "colemak qwerty"
      var edits: [WebsiteConfigPracticeEdit] = []
      kind.submit(form) { edits.append($0); return "applied" }
      let deadline = ContinuousClock.now.advanced(by: .seconds(3))
      while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
      XCTAssertFalse(form.isWorking)
      XCTAssertEqual(edits, kind == .polyglot ? [.polyglotLanguages(["german", "spanish"])] : [.layoutFluidLayouts(["colemak", "qwerty"])])
      XCTAssertEqual(form.polyglotLanguages, "german spanish")
      XCTAssertEqual(form.layoutFluidLayouts, "colemak qwerty")
    }
  }

  func testRemovingCommandCancelsPendingFormAndSuppressesLateSuccess() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    for kind in WebsiteSequenceCommandKind.allCases {
      try await assertRemovalCancels(draft: draft, kind: kind)
    }
  }
  private func assertRemovalCancels(draft: WebsiteConfigNativeDraft, kind: WebsiteSequenceCommandKind) async throws {
    let form = WebsiteConfigPracticeEditForm(draft: draft)
    let host = NSHostingView(rootView: AnyView(WebsiteSequenceCommandView(form: form, kind: kind, canApply: true,
      apply: { _ in "unused" })))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 540, height: 340),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    render(host)
    var reply: CheckedContinuation<String, Never>?
    defer { reply?.resume(returning: "cleanup") }
    kind.submit(form) { _ in await withCheckedContinuation { reply = $0 } }
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
