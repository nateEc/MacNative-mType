import Foundation
import XCTest
@testable import Typebar

@MainActor final class ConfigurationNoticeTests: XCTestCase {
  private let current = SavedTestPreset(configuration: .words(25))

  func testActualConfigurationConflictHelperKeepsOrdinaryAndLockedVisibilityDistinct() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    ConfigurationNoticeFeedback.conflict("Owned conflict", notices: center)
    ConfigurationNoticeFeedback.conflict("Owned locked", notices: center, locked: true)
    XCTAssertEqual(center.active.map(\.durationMilliseconds), [3_000, 5_000])
    XCTAssertEqual(center.active.map(\.important), [true, false])
    XCTAssertEqual(center.visible(focused: true).map(\.entry.message), ["Owned locked"])
    XCTAssertTrue(center.history.allSatisfy { $0.level == .notice && $0.details == nil })
  }

  func testKnownBreaksAndEveryPinnedEscapeAreDecodedExactlyOnce() {
    let message = "自有 &amp; &lt; &gt; &quot; &#39; &#x2F; &#x60;<br>next<br/>line<br />end"
    XCTAssertEqual(LocalNoticeMessagePresentation.make(message, containsHTML: true),
      .init(text: "自有 & < > \" ' / `\nnext\nline\nend", usesLiteralFallback: false))
    XCTAssertEqual(LocalNoticeMessagePresentation.make("&amp;lt;br&amp;gt;<br>&lt;br&gt;", containsHTML: true).text,
      "&lt;br&gt;\n<br>")
    XCTAssertEqual(LocalNoticeMessagePresentation.make("a<BR>b", containsHTML: true).text, "a\nb")
  }

  func testUnflaggedTextAndUnsupportedMarkupAreNeverInterpretedOrPartiallyDecoded() {
    for message in ["<script>owned()</script>", "before<br><img src='https://example.invalid/private'>",
      "<a href='file:///owned'>link</a>", "<b>bold</b>", "unterminated <br", "<br onclick='owned()'>"] {
      XCTAssertEqual(LocalNoticeMessagePresentation.make(message, containsHTML: true),
        .init(text: message, usesLiteralFallback: true))
    }
    let raw = "**Owned** &lt;x&gt;<br>\n[link](https://example.invalid)"
    XCTAssertEqual(LocalNoticeMessagePresentation.make(raw, containsHTML: false),
      .init(text: raw, usesLiteralFallback: false))
    XCTAssertEqual(LocalNoticeMessagePresentation.make("&unknown; &amp", containsHTML: true).text, "&unknown; &amp")
  }

  func testPresentationDoesNotChangeRetainedMessageOrCopiedDetails() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let message = "Owned<br>&lt;br&gt;&amp;lt;"
    center.post(message, options: .init(durationMilliseconds: 0, details: .string("Owned"), containsHTML: true))
    let entry = try XCTUnwrap(center.history.last)
    XCTAssertEqual(LocalNoticeMessagePresentation.make(entry.message, containsHTML: entry.containsHTML).text, "Owned\n<br>&lt;")
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(entry.detailsText().utf8)) as? [String: Any])
    XCTAssertEqual(payload["message"] as? String, message)
    XCTAssertEqual(center.history.last?.message, message)
  }

  func testRealNativeLinkApplicationReportsSuccessOnlyAfterAcceptedCallback() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let preset = SavedTestPreset(configuration: .timed(seconds: 60))
    let link = try TestConfigurationShare.link(for: preset)
    var accepted: SavedTestPreset?
    let result = TestConfigurationShareActions.apply(link, current: current, challenges: [], notices: center,
      applyPreset: { value in
        XCTAssertTrue(center.history.isEmpty, "Do not publish success before application")
        accepted = value; return value
      }, loadChallenge: { _ in XCTFail("Not a challenge link"); return .rejected })
    XCTAssertEqual(accepted, preset); XCTAssertEqual(result.outcome, .applied); XCTAssertTrue(result.shouldDismiss)
    XCTAssertEqual(center.history.last?.level, .success)
    XCTAssertEqual(center.active.first?.durationMilliseconds, 10_000)
    XCTAssertTrue(center.history.last?.message.contains("时长：60 秒") == true)
    XCTAssertFalse(center.history.last?.message.contains(link) == true)
  }

  func testRejectedApplicationStaysOpenAndNeverClaimsSuccess() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let result = TestConfigurationShareActions.apply(try TestConfigurationShare.link(for: current), current: current,
      challenges: [], notices: center, applyPreset: { _ in nil }, loadChallenge: { _ in .rejected })
    XCTAssertEqual(result.outcome, .rejected); XCTAssertFalse(result.shouldDismiss)
    XCTAssertEqual(center.history.map(\.level), [.notice]); XCTAssertTrue(center.active.first?.important == true)
    XCTAssertEqual(result.status, center.history.last?.message)
  }

  func testSuccessSummaryUsesCanonicalAppliedSnapshotRatherThanRequestedValues() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let requested = SavedTestPreset(configuration: .timed(seconds: 60))
    let canonical = SavedTestPreset(configuration: .timed(seconds: 30))
    var applied: SavedTestPreset?
    let result = TestConfigurationShareActions.apply(try TestConfigurationShare.link(for: requested), current: current,
      challenges: [], notices: center, applyPreset: { _ in applied = canonical; return canonical },
      loadChallenge: { _ in .rejected })
    XCTAssertEqual(applied, canonical); XCTAssertTrue(result.shouldDismiss)
    XCTAssertTrue(center.history.last?.message.contains("时长：30 秒") == true)
    XCTAssertFalse(center.history.last?.message.contains("时长：60 秒") == true)
  }

  func testInvalidLinksNeverReachApplicationOrRetainUntrustedInput() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    for link in ["typebar://test?preset=PRIVATE_INVALID_PAYLOAD", "https://private.example/?testSettings=PRIVATE_BAD"] {
      let result = TestConfigurationShareActions.apply(link, current: current, challenges: [], notices: center,
        applyPreset: { _ in XCTFail("Bad decoder input must not apply"); return nil },
        loadChallenge: { _ in XCTFail("Bad decoder input must not select a challenge"); return .applied })
      XCTAssertFalse(result.shouldDismiss); XCTAssertNotNil(result.status)
    }
    XCTAssertFalse(center.history.contains { $0.message.contains("PRIVATE") || $0.message.contains("private.example") })
    XCTAssertTrue(center.history.allSatisfy { $0.details == nil && $0.level == .notice })
  }

  func testChallengeSelectionDistinguishesAppliedSetupAndRejected() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
    for outcome in [TestConfigurationApplyOutcome.applied, .requiresSetup, .rejected] {
      center.clearForAccountChange()
      let result = TestConfigurationShareActions.apply("https://example.invalid/?challenge=\(challenge.id)", current: current,
        challenges: [challenge], notices: center,
        applyPreset: { _ in XCTFail("Challenge uses its own callback"); return nil },
        loadChallenge: { value in XCTAssertEqual(value.id, challenge.id); return outcome })
      XCTAssertEqual(result.outcome, outcome); XCTAssertEqual(result.shouldDismiss, outcome != .rejected)
      XCTAssertEqual(center.history.last?.level, outcome == .applied ? .success : .notice)
      if outcome == .requiresSetup { XCTAssertFalse(center.history.last?.message.contains("已应用") == true) }
    }
  }

  func testCopyOutcomeUsesProductionHelperWithoutKeepingLinkOrPayload() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    var writes: [String] = []
    let secret = "typebar://test?preset=OWNED_PRIVATE_PAYLOAD"
    let success = TestConfigurationShareActions.copy(secret, notices: center) { writes.append($0); return true }
    let failure = TestConfigurationShareActions.copy(secret, notices: center) { writes.append($0); return false }
    XCTAssertEqual(writes, [secret, secret]); XCTAssertNotEqual(success, failure)
    XCTAssertEqual(center.history.map(\.level), [.success, .error])
    XCTAssertFalse(center.history.contains { $0.message.contains(secret) || $0.details != nil })
  }

  func testCustomTextSummaryKeepsOnlySelectionMetadataNotPracticeOrLinkContent() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let secret = "OWNED_PRIVATE_SENTENCE & <br> ' / `"
    let preset = SavedTestPreset(configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .expert, rules: .init()), customText: secret)
    let link = try TestConfigurationShare.link(for: preset)
    let result = TestConfigurationShareActions.apply(link, current: current, challenges: [], notices: center,
      applyPreset: { XCTAssertEqual($0.customText, secret); return $0 }, loadChallenge: { _ in .rejected })
    XCTAssertTrue(result.shouldDismiss)
    XCTAssertTrue(center.history.last?.message.contains("自定义文本：已应用") == true)
    XCTAssertFalse(center.history.last?.message.contains(secret) == true)
    XCTAssertFalse(center.history.last?.message.contains(link) == true)
  }

  func testNativeFormattingAndLegacyFieldMaskAgainstCompletePinnedProducers() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned checkout and QA dependencies")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-configuration-notices.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let rendered = try XCTUnwrap(document["rendered"] as? [[String: String]])
    XCTAssertEqual(rendered.count, 9)
    for value in rendered {
      let message = try XCTUnwrap(value["html"])
      XCTAssertEqual(LocalNoticeMessagePresentation.make(message, containsHTML: true),
        .init(text: try XCTUnwrap(value["plain"]), usesLiteralFallback: false))
    }
    let legacy = try XCTUnwrap(document["legacy"] as? [[String: Any]])
    XCTAssertEqual(legacy.count, 8)
    for value in legacy {
      let center = LocalNoticeCenter(); defer { center.clearAll() }
      let link = try XCTUnwrap(value["link"] as? String), fields = try XCTUnwrap(value["fields"] as? [Int])
      let decoded = try LegacyTestSettingsLinkImporter.importedPreset(from: link, current: current)
      XCTAssertEqual(decoded.noticeFields.map(\.rawValue), fields)
      var applied: SavedTestPreset?
      let result = TestConfigurationShareActions.apply(link, current: current, challenges: [], notices: center,
        applyPreset: { applied = $0; return $0 }, loadChallenge: { _ in XCTFail("Not a challenge"); return .rejected })
      XCTAssertEqual(applied, decoded.preset); XCTAssertTrue(result.shouldDismiss)
      XCTAssertEqual(center.history.count, fields.isEmpty ? 0 : 1)
      if !fields.isEmpty {
        XCTAssertEqual(center.history.last?.message, TestConfigurationShareActions.summary(decoded.preset, fields: decoded.noticeFields))
        XCTAssertEqual(center.active.first?.durationMilliseconds, 10_000)
        XCTAssertFalse(center.history.last?.message.contains(link) == true)
        if let text = decoded.preset.customText { XCTAssertFalse(center.history.last?.message.contains(text) == true) }
      }
    }
  }
}
