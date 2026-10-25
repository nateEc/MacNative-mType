import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigPracticeEditorTests: XCTestCase {
  private func parameters() throws -> WebsiteConfigNativeTestParameters {
    try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4,"time":15}"#,
      pointsPerRem: 16, context: .init()).testParameters
  }
  private func settle(_ form: WebsiteConfigPracticeEditForm) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking)
  }
  func testPolyglotInputMatchesPinnedCommandConversionAndPrevalidation() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable { let raw: String, converted: [String], canSubmit: Bool }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-polyglot-list-command.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 72)
    for fixture in fixtures {
      let form = WebsiteConfigPracticeEditForm(parameters: try parameters())
      form.polyglotLanguages = fixture.raw
      var edits: [WebsiteConfigPracticeEdit] = []
      form.startPolyglotLanguages { edits.append($0); return "applied" }
      await settle(form)
      XCTAssertEqual(edits, fixture.canSubmit ? [.polyglotLanguages(fixture.converted)] : [], fixture.raw)
      XCTAssertEqual(form.polyglotLanguages, fixture.raw, "Invalid or normalized input must not be silently rewritten")
      if !fixture.canSubmit { XCTAssertTrue(form.message?.contains("语言 ID") == true) }
    }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"customPolyglot":["german","spanish"]}"#,
      pointsPerRem: 16, context: .init())
    XCTAssertEqual(WebsiteConfigPracticeEditForm(draft: draft).polyglotLanguages, "german spanish")
  }
  func testLimitValidationPreservesInputAndForwardsOnlyExplicitParameter() async throws {
    let form = WebsiteConfigPracticeEditForm(parameters: try parameters())
    var edits: [WebsiteConfigPracticeEdit] = []
    let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String = { edits.append($0); return "saved" }
    XCTAssertEqual(form.limit, "4")
    for text in ["", "-1", "2.5", "nan", "inf", "999999999999999999999999"] {
      form.limit = text; form.startLimit(timed: false, apply: apply)
      XCTAssertFalse(form.isWorking); XCTAssertEqual(form.limit, text)
      XCTAssertTrue(form.message?.contains("非负整数") == true)
    }
    XCTAssertTrue(edits.isEmpty)
    form.limit = " 0 "; form.startLimit(timed: false, apply: apply); await settle(form)
    form.limit = "30"; form.startLimit(timed: true, apply: apply); await settle(form)
    XCTAssertEqual(edits, [.words(0), .time(30)])
    XCTAssertEqual(form.message, "saved")
  }
  func testCancellationSingleFlightAndFailureNeverShowLateSuccess() async throws {
    let form = WebsiteConfigPracticeEditForm(parameters: try parameters())
    var continuation: CheckedContinuation<String, Never>?
    var edits: [WebsiteConfigPracticeEdit] = []
    let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String = {
      edits.append($0); return await withCheckedContinuation { continuation = $0 }
    }
    form.start(.mode(.time), apply: apply); form.start(.words(5), apply: apply)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while continuation == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertEqual(edits, [.mode(.time)]); XCTAssertNotNil(continuation)
    form.cancel(); let message = form.message
    continuation?.resume(returning: "late success")
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(form.message, message); XCTAssertFalse(form.isWorking)
    form.start(.words(5), apply: { _ in throw WebsiteConfigImportWorkflowError.conflict })
    await settle(form)
    XCTAssertTrue(form.message?.contains("未应用") == true)
    XCTAssertEqual(form.limit, "4")
  }
  func testFullDraftSeedsDifficultyAndRetainsDuplicateQuoteGroupsUntilExplicitApplication() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"quote","difficulty":"expert","quoteLength":[0,0,1]}"#,
      pointsPerRem: 16, context: .init())
    let form = WebsiteConfigPracticeEditForm(draft: draft)
    XCTAssertEqual(form.difficulty, .expert); XCTAssertEqual(form.quoteLengths, [0,0,1])
    XCTAssertEqual(WebsiteConfigPracticeEditForm.quoteChoices.map(\.groups), [[0,1,2,3], [0], [1], [2], [3]])
    var edits: [WebsiteConfigPracticeEdit] = []
    form.start(.quoteLengths(form.quoteLengths), apply: { edits.append($0); return "applied" })
    await settle(form)
    XCTAssertEqual(edits, [.quoteLengths([0,0,1])])
    XCTAssertEqual(form.quoteLengths, [0,0,1])
  }
  func testLanguageSelectionUsesWebsiteIdentityAndDoesNotTreatNativeMixAsALanguage() async throws {
    let form = WebsiteConfigPracticeEditForm(parameters: try parameters())
    var edits: [WebsiteConfigPracticeEdit] = []
    form.language = .mixedLanguages
    form.startLanguage(apply: { edits.append($0); return "unexpected" })
    XCTAssertFalse(form.isWorking); XCTAssertTrue(edits.isEmpty)
    XCTAssertTrue(form.message?.contains("Polyglot") == true)
    form.language = .arabic
    form.startLanguage(apply: { edits.append($0); return "applied" }); await settle(form)
    XCTAssertEqual(edits, [.language("arabic")])
    XCTAssertFalse(WebsiteConfigPracticeEditForm.languages.contains(.mixedLanguages))
  }

  func testResumeUsesSameSingleFlightAndCancellationDoesNotPromiseRollback() async throws {
    let form = WebsiteConfigPracticeEditForm(parameters: try parameters())
    var continuation: CheckedContinuation<String, Never>?
    var calls = 0
    form.resume { calls += 1; return await withCheckedContinuation { continuation = $0 } }
    form.resume { calls += 1; return "unexpected" }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while continuation == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertEqual(calls, 1); XCTAssertTrue(form.isWorking)
    form.cancel()
    XCTAssertTrue(form.message?.contains("已保存的设置保留") == true)
    let cancelled = form.message
    continuation?.resume(returning: "late resume")
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(form.message, cancelled)
    form.resume { throw WebsiteConfigSavedPreparationError(underlying: NSError(domain: "owned-provider", code: 1)) }
    await settle(form)
    XCTAssertTrue(form.message?.contains("设置已保存") == true)
    XCTAssertTrue(form.message?.contains("继续准备") == true)
  }

  @MainActor @Observable final class PendingState { var pending = false }
  private func render(_ host: NSView) {
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  }
  @MainActor private struct RetainedEditor: View {
    let state: PendingState
    let form: WebsiteConfigPracticeEditForm
    let parameters: WebsiteConfigNativeTestParameters
    var body: some View {
      WebsiteConfigPracticeEditor(form: form, parameters: parameters, canEdit: true,
        pendingPreparation: state.pending, resume: { "resumed" }, apply: { _ in "applied" })
    }
  }

  func testSavedPendingPresentationKeepsEditorTaskAliveWithoutShowingWindow() async throws {
    let state = PendingState(), form = WebsiteConfigPracticeEditForm(parameters: try parameters())
    let host = NSHostingView(rootView: RetainedEditor(state: state, form: form, parameters: try parameters()))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 340, height: 760),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    var continuation: CheckedContinuation<String, Never>?
    form.start(.mode(.quote), apply: { _ in await withCheckedContinuation { continuation = $0 } })
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while continuation == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertNotNil(continuation)
    state.pending = true
    render(host)
    XCTAssertTrue(form.isWorking, "Showing accepted departure must not disappear/cancel the editor")
    XCTAssertFalse(window.isVisible)
    continuation?.resume(returning: "ready"); await settle(form)
    XCTAssertEqual(form.message, "ready")
  }
  func testPendingEditorRendersLightAndDarkWithoutDispatchingResume() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4}"#,
      pointsPerRem: 16, context: .init())
    for (width, saved) in [(340, true), (340, false), (520, true), (520, false)] {
      for dark in [false, true] {
        var calls = 0
        let view = WebsiteConfigPracticeEditor(draft: draft, canEdit: true, pendingPreparation: true,
          configurationWasSaved: saved,
          resume: { calls += 1; return "unexpected" }, apply: { _ in calls += 1; return "unexpected" })
          .padding(20).frame(width: CGFloat(width), height: 760)
          .background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: CGFloat(width), height: 760),
          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
        defer { window.contentView = nil; window.close() }
        render(host)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/typebar-active-edit-\(saved ? "pending" : "restored")-\(width)-\(dark ? "dark" : "light").png"))
        XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
      }
    }
  }

  func testRecoveryReasonsRenderWithoutOpeningWindow() throws {
    let view = WebsiteQuoteRecoveryNotice(recoveries: [.allLengths, .wordsMode])
      .padding(16).frame(width: 340, height: 160, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 340, height: 160),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    render(host)
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/typebar-quote-recovery-notice.png"))
    XCTAssertFalse(window.isVisible)
    XCTAssertGreaterThan(png.count, 1000)
  }
  func testEditorRendersLightAndDarkWithoutShowingWindowOrApplying() throws {
    for quoted in [false, true] {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(quoted
        ? #"{"mode":"quote","difficulty":"expert","quoteLength":[0,0,1]}"#
        : #"{"mode":"words","words":4,"difficulty":"master"}"#, pointsPerRem: 16, context: .init())
      let parameters = draft.testParameters
      for width in [340, 520] {
        for dark in [false, true] {
          var calls = 0
          let form = WebsiteConfigPracticeEditForm(draft: draft)
          let view = WebsiteConfigPracticeEditor(form: form, parameters: parameters, canEdit: true,
            apply: { _ in calls += 1; return "unexpected" })
            .padding(20).frame(width: CGFloat(width), height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
          let host = NSHostingView(rootView: view)
          let window = NSWindow(contentRect: .init(x: 0, y: 0, width: CGFloat(width), height: 680),
            styleMask: .borderless, backing: .buffered, defer: false)
          window.isReleasedWhenClosed = false
          window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
          defer { window.contentView = nil; window.close() }
          host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
          try png.write(to: URL(fileURLWithPath: "/tmp/typebar-content-editor-\(quoted ? "quote" : "words")-\(width)-\(dark ? "dark" : "light").png"))
          XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
        }
      }
    }
  }
}
