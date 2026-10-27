import XCTest
@testable import Typebar

@MainActor final class WebsiteSharedLinkImportTests: XCTestCase {
  private let json = #"["words","17",null,true,false,null,"expert",null]"#
  private func link(_ json: String, origin: String = "typebar://test") throws -> String {
    origin + "?testSettings=" + (try XCTUnwrap(URICompressedPayload.compress(json)))
  }

  func testDecodesNativeAndWebLinksLocallyWithoutNormalizingRawJSON() throws {
    let raw = #"["custom",null,{"text":["\ud800"],"mode":"repeat","limit":{"mode":"time","value":1e999},"pipeDelimiter":false},null,null,null,null,null]"#
    for origin in ["typebar://test", "https://offline.invalid/path", "https://owned:example@offline.invalid/path"] {
      XCTAssertEqual(try WebsiteSharedLinkImport.json(from: link(raw, origin: origin)), raw)
    }
    XCTAssertNil(try WebsiteSharedLinkImport.json(from: "typebar://test?preset=unchanged"))
  }

  func testRejectsAmbiguousOrMalformedSettingsBeforeCallingReceiver() throws {
    let valid = try link(json)
    for invalid in [valid + "&testSettings=bad", valid.replacingOccurrences(of: "typebar://test", with: "typebar://other"),
      "https://offline.invalid/?testSettings=", "file:///tmp/test?testSettings=abc",
      "https://offline.invalid/?testSettings=" + String(repeating: "x", count: 32_769)] {
      XCTAssertThrowsError(try WebsiteSharedLinkImport.json(from: invalid), invalid)
    }
  }

  func testAsyncRouteUsesWholeProfileReceiverAndRetainsPartialApplicationPanel() async throws {
    let notices = LocalNoticeCenter(); defer { notices.clearAll() }
    var received: [String] = []
    let result = await TestConfigurationShareActions.applyAsync(try link(json), current: .init(configuration: .words(5)),
      challenges: [], notices: notices, applyWebsiteSettings: { value in
        received.append(value)
        return .retained("设置已接收，等待继续准备。")
      }, applyPreset: { _ in XCTFail("Cannot flatten the website profile"); return nil },
      loadChallenge: { _ in XCTFail("Cannot load challenge"); return .rejected })
    XCTAssertEqual(received, [json]); XCTAssertFalse(result.shouldDismiss)
    XCTAssertEqual(result.status, "设置已接收，等待继续准备。")
    XCTAssertFalse(notices.history.contains { $0.level == .success })
  }

  func testAsyncRoutePreservesNativeFullPresetAndRejectsBadPayloadWithoutFallback() async throws {
    let notices = LocalNoticeCenter(); defer { notices.clearAll() }
    let preset = SavedTestPreset(configuration: .words(12))
    var applied = 0, received = 0
    let native = try TestConfigurationShare.link(for: preset)
    let result = await TestConfigurationShareActions.applyAsync(native, current: preset,
      challenges: [], notices: notices, applyWebsiteSettings: { _ in received += 1; return .applied("done") },
      applyPreset: { applied += 1; return $0 }, loadChallenge: { _ in .rejected })
    XCTAssertTrue(result.shouldDismiss); XCTAssertEqual(applied, 1); XCTAssertEqual(received, 0)
    let invalid = await TestConfigurationShareActions.applyAsync("typebar://test?testSettings=bad", current: preset,
      challenges: [], notices: notices, applyWebsiteSettings: { _ in received += 1; return .applied("done") },
      applyPreset: { _ in applied += 1; return preset }, loadChallenge: { _ in .rejected })
    XCTAssertFalse(invalid.shouldDismiss); XCTAssertEqual(applied, 1); XCTAssertEqual(received, 0)
  }

  func testWebQuerySelectionMatchesCompletePinnedParameterHelper() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference for the actual URL query helper")
    }
    struct Output: Decodable {
      struct Fixture: Decodable { let query: String, value: String?, failed: Bool }
      let fixtures: [Fixture]
    }
    let token = try XCTUnwrap(URICompressedPayload.compress(json))
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-shared-link-query.mjs").path, reference, token]
    process.standardOutput = pipe
    try process.run()
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: bytes).fixtures
    XCTAssertEqual(fixtures.count, 10)
    for fixture in fixtures {
      let link = "https://offline.invalid/" + fixture.query
      if !fixture.failed, fixture.value == token {
        XCTAssertEqual(try WebsiteSharedLinkImport.json(from: link), json, fixture.query)
      } else if !fixture.failed, fixture.value == nil {
        XCTAssertNil(try WebsiteSharedLinkImport.json(from: link), fixture.query)
      } else {
        XCTAssertThrowsError(try WebsiteSharedLinkImport.json(from: link), fixture.query)
      }
    }
  }

  func testWebChallengeKeepsExistingPriorityWhenSettingsAreAlsoPresent() async throws {
    let notices = LocalNoticeCenter(); defer { notices.clearAll() }
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.all.first)
    let mixed = try link(json, origin: "https://offline.invalid/") + "&challenge=" + challenge.id
    var received = 0, loaded = 0
    let result = await TestConfigurationShareActions.applyAsync(mixed, current: .init(configuration: .words(5)),
      challenges: [challenge], notices: notices, applyWebsiteSettings: { _ in received += 1; return .applied("wrong") },
      applyPreset: { _ in XCTFail("Cannot apply a preset"); return nil }, loadChallenge: {
        XCTAssertEqual($0.id, challenge.id); loaded += 1; return .applied
      })
    XCTAssertTrue(result.shouldDismiss); XCTAssertEqual(received, 0); XCTAssertEqual(loaded, 1)
  }

  func testCancellationBeforeAdmissionHasNoWritesOrSuccessNotice() async throws {
    let notices = LocalNoticeCenter(); defer { notices.clearAll() }
    let incoming = try link(json)
    var calls = 0
    let task = Task { @MainActor in
      await TestConfigurationShareActions.applyAsync(incoming, current: .init(configuration: .words(5)),
        challenges: [], notices: notices, applyWebsiteSettings: { _ in calls += 1; return .applied("wrong") },
        applyPreset: { _ in calls += 1; return nil }, loadChallenge: { _ in calls += 1; return .rejected })
    }
    task.cancel()
    let result = await task.value
    XCTAssertFalse(result.shouldDismiss); XCTAssertEqual(calls, 0); XCTAssertTrue(notices.history.isEmpty)
  }
}
