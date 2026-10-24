import AppKit
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
            .padding(20).frame(width: CGFloat(width), height: 460)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
          let host = NSHostingView(rootView: view)
          let window = NSWindow(contentRect: .init(x: 0, y: 0, width: CGFloat(width), height: 460),
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
