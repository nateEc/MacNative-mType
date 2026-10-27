import XCTest
import AppKit
import SwiftUI
@testable import Typebar

@MainActor final class WebsiteTestSettingsShareTests: XCTestCase {
  func testSelectedFieldsAgainstCompletePinnedURLProducer() throws {
    let output = try oracle()
    XCTAssertEqual(output.fixtures.count, 1280)
    for fixture in output.fixtures {
      var runtime = try XCTUnwrap(WebsiteConfigJSONReader.read(fixture.runtimeJSON).importFields)
      let selected = Set(WebsiteTestSettingsShare.Field.allCases.filter { fixture.mask & (1 << $0.rawValue) != 0 })
      let custom = try WebsiteConfigJSONReader.read(fixture.customJSON)
      let expected = try WebsiteConfigJSONReader.read(fixture.tupleJSON)
      let snapshot = WebsiteTestSettingsShare.Snapshot(runtime: runtime, customText: custom, quoteID: fixture.quoteID)
      let link = try WebsiteTestSettingsShare.link(snapshot, selected: selected, origin: "https://owned.invalid")
      let token = try XCTUnwrap(URLComponents(string: link)?.queryItems?.first?.value)
      let json = try XCTUnwrap(URICompressedPayload.decompress(token))
      XCTAssertEqual(try WebsiteConfigJSONReader.read(json), expected, "mask \(fixture.mask)")
      runtime["minWpmCustomSpeed"] = .number(.infinity)
      runtime["minBurstCustomSpeed"] = .number(.infinity)
      XCTAssertEqual(try WebsiteTestSettingsShare.link(.init(runtime: runtime, customText: custom, quoteID: fixture.quoteID),
        selected: selected, origin: "https://owned.invalid"), link)
    }
  }

  func testNativeCompressionMatchesPinnedLibraryAndExistingDecoder() throws {
    for fixture in try oracle().compression {
      let compressed = try XCTUnwrap(URICompressedPayload.compress(fixture.text))
      XCTAssertEqual(compressed, fixture.compressed)
      XCTAssertEqual(URICompressedPayload.decompress(compressed), fixture.text)
    }
    XCTAssertNil(URICompressedPayload.compress(String(repeating: "x", count: 65_537)))
  }

  func testLargeEmojiSourceLinkDoesNotExceedBoundThroughUnnecessaryEscaping() throws {
    let source = try oracle().emoji
    let custom = try WebsiteConfigJSONReader.read(source.customJSON)
    let snapshot = WebsiteTestSettingsShare.Snapshot(runtime: ["mode": .string("custom")], customText: custom)
    let link = try WebsiteTestSettingsShare.link(snapshot, selected: [.mode, .customText])
    let token = try XCTUnwrap(URLComponents(string: link)?.queryItems?.first?.value)
    let json = try XCTUnwrap(URICompressedPayload.decompress(token))
    XCTAssertLessThan(json.utf16.count, 65536)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(json), try WebsiteConfigJSONReader.read(source.tupleJSON))
  }

  func testCompactJSONPreservesCodeUnitsWithoutChangingDefaultStoredSpelling() throws {
    let units: [UInt16] = [0x5b57, 0xd83d, 0xde00, 10, 9, 0xd800, 34, 92, 0xdfff]
    let value = WebsiteConfigValue.string(units: units)
    let old = WebsiteConfigJSONWriter.write(value)
    XCTAssertEqual(old, #""\u5b57\ud83d\ude00\u000a\u0009\ud800\"\\\udfff""#)
    let compact = WebsiteConfigJSONWriter.write(value, asciiOnly: false)
    XCTAssertTrue(compact.contains("字😀"))
    XCTAssertTrue(compact.contains(#"\n\t\ud800"#))
    XCTAssertEqual(try WebsiteConfigJSONReader.read(compact).stringUnits, units)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(old).stringUnits, units)
    XCTAssertEqual(WebsiteConfigJSONWriter.write(.number(17)), "17.0")
    XCTAssertEqual(WebsiteConfigJSONWriter.write(.number(17), asciiOnly: false), "17")
  }

  func testSelectionVisibilityAndUnavailableUnselectedValues() throws {
    let fields = WebsiteTestSettingsShare.Field.allCases
    XCTAssertEqual(fields.filter { $0.isVisible(mode: "zen") }, [.mode, .funbox])
    XCTAssertEqual(fields.filter { $0.isVisible(mode: "custom") }, [.mode, .customText, .punctuation, .numbers, .language, .difficulty, .funbox])
    XCTAssertEqual(fields.filter { $0.isVisible(mode: "words") }, [.mode, .parameter, .punctuation, .numbers, .language, .difficulty, .funbox])
    let unavailable = WebsiteTestSettingsShare.Snapshot(runtime: [:], hasUnmappedQuote: true)
    let empty = try WebsiteTestSettingsShare.link(unavailable, selected: [])
    let token = try XCTUnwrap(URLComponents(string: empty)?.queryItems?.first?.value)
    XCTAssertEqual(URICompressedPayload.decompress(token), "[null,null,null,null,null,null,null,null]")
    XCTAssertThrowsError(try WebsiteTestSettingsShare.link(unavailable, selected: [.mode]))
    let owned = WebsiteTestSettingsShare.Snapshot(runtime: ["mode": .string("quote")], hasUnmappedQuote: true)
    XCTAssertNoThrow(try WebsiteTestSettingsShare.link(owned, selected: [.mode]))
    XCTAssertThrowsError(try WebsiteTestSettingsShare.link(owned, selected: [.parameter]))
  }

  func testIndependentCustomSourceAndLegacyIncomingLinkPreserveOtherRules() throws {
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.customText = "own alpha|own beta"
    scope.customCompletion = .sections
    scope.parameterMemory = .init(duration: 30, wordLimit: 25, customTextDuration: 30, customTextWordLimit: 25, customTextSectionLimit: 4)
    scope.customOrdering = .shuffled; scope.customPipeDelimiter = true
    let custom = try XCTUnwrap(WebsiteTestSettingsShare.customText(in: scope))
    let snapshot = WebsiteTestSettingsShare.Snapshot(runtime: ["mode": .string("custom"), "numbers": .bool(true)], customText: custom)
    let link = try WebsiteTestSettingsShare.link(snapshot, selected: [.mode, .customText, .numbers])
    let current = SavedTestPreset(configuration: .words(25, rules: .init(strictSpace: true)))
    let imported = try LegacyTestSettingsLinkImporter.preset(from: link, current: current)
    XCTAssertEqual(imported.configuration.mode, .custom)
    XCTAssertEqual(imported.configuration.rules, current.configuration.rules)
    XCTAssertEqual(imported.configuration.contentOptions.includeNumbers, true)
    XCTAssertEqual(imported.configuration.customTextCompletion, .sections)
    XCTAssertEqual(imported.configuration.customTextSectionLimit, 4)
    XCTAssertEqual(imported.configuration.customTextOrdering, .shuffled)
    XCTAssertEqual(imported.customText, "own alpha|own beta")
    scope.customTextRecoveryBlocked = true
    XCTAssertNil(WebsiteTestSettingsShare.customText(in: scope))
    XCTAssertNoThrow(try WebsiteTestSettingsShare.link(.init(runtime: ["mode": .string("words")]), selected: [.mode]))
  }

  func testProductionControllerDefaultsRetainsSelectionAndCopiesLatestSnapshot() throws {
    let center = LocalNoticeCenter()
    defer { center.clearAll() }
    var snapshot = WebsiteTestSettingsShare.Snapshot(runtime: ["mode": .string("time"), "time": .number(30)])
    var writes: [String] = []
    let controller = WebsiteTestSettingsShareController(read: { snapshot }, notices: center,
      write: { writes.append($0); return true })
    XCTAssertTrue(controller.selected.isEmpty)
    XCTAssertFalse(controller.isEnabled(.parameter))
    controller.selected = [.mode, .parameter]
    let oldLink = try XCTUnwrap(controller.link)
    snapshot = .init(runtime: ["mode": .string("words"), "words": .number(17)])
    controller.copy()
    XCTAssertEqual(writes, [try XCTUnwrap(controller.link)])
    XCTAssertNotEqual(writes.first, oldLink)
    controller.selected.remove(.mode)
    XCTAssertFalse(controller.isEnabled(.parameter))
    XCTAssertTrue(controller.selected.contains(.parameter))
    controller.copy()
    let token = try XCTUnwrap(URLComponents(string: writes.last!)?.queryItems?.first?.value)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(XCTUnwrap(URICompressedPayload.decompress(token))),
      .array([.null, .string("17"), .null, .null, .null, .null, .null, .null]))
    snapshot = .init(runtime: ["mode": .string("quote")], hasUnmappedQuote: true)
    let before = writes.count
    controller.copy()
    XCTAssertEqual(writes.count, before)
    XCTAssertNotNil(controller.status)
    XCTAssertEqual(controller.failureMessage, WebsiteTestSettingsShare.Failure.unmappedQuote.errorDescription)
  }

  func testLongURLWarningAndClipboardRefusalKeepManualLinkAvailable() throws {
    let center = LocalNoticeCenter()
    defer { center.clearAll() }
    // Owned, varied input rather than reference word or quote content.
    let text = String((0..<4000).compactMap { UnicodeScalar(0x4e00 + $0) }.map(Character.init))
    let snapshot = WebsiteTestSettingsShare.Snapshot(runtime: ["mode": .string("custom")],
      customText: .object(["text": .array([.string(text)]), "mode": .string("repeat"),
        "limit": .object(["value": .number(1), "mode": .string("word")]), "pipeDelimiter": .bool(false)]))
    let controller = WebsiteTestSettingsShareController(read: { snapshot }, notices: center, write: { _ in false })
    controller.selected = [.mode, .customText]
    let link = try XCTUnwrap(controller.link)
    XCTAssertTrue(controller.isLong)
    controller.copy()
    XCTAssertEqual(controller.link, link)
    XCTAssertFalse(center.history.contains { $0.level == .success })
    XCTAssertNotNil(controller.status)
  }

  func testProductionShareViewHostsNonemptyReadonlyLinkWithoutShowingAWindow() throws {
    let notices = LocalNoticeCenter()
    defer { notices.clearAll() }
    let snapshot = WebsiteTestSettingsShare.Snapshot(runtime: ["mode": .string("words"), "words": .number(17)])
    let view = TestConfigurationShareView(currentPreset: .init(configuration: .words(17)),
      websiteSnapshot: { snapshot }, notices: notices, onApply: { $0 })
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 560, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    func textViews(_ view: NSView) -> [WebsiteConfigCopyTextView] {
      (view as? WebsiteConfigCopyTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }
    let text = try XCTUnwrap(textViews(host).first { $0.accessibilityIdentifier() == "website-test-settings-url" })
    let expected = try WebsiteTestSettingsShare.link(snapshot, selected: [])
    XCTAssertFalse(text.string.isEmpty)
    XCTAssertTrue(text.string.utf8.elementsEqual(expected.utf8))
    XCTAssertNotNil(text.textStorage); XCTAssertNotNil(text.layoutManager)
    XCTAssertFalse(text.isEditable); XCTAssertTrue(text.isSelectable)
    text.selectAll(nil)
    XCTAssertEqual(text.selectedRange().length, expected.utf16.count)
    XCTAssertFalse(window.isVisible)
  }

  func testCustomShareUsesWholeFiniteSourceInsteadOfDisplayedChunk() throws {
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.customText = "chunk"
    scope.preparedCustomSections = ["chunk"]
    scope.finiteTextSource = "whole owned source"
    let custom = try XCTUnwrap(WebsiteTestSettingsShare.customText(in: scope)?.importFields)
    XCTAssertEqual(custom["text"], .array([.string("whole"), .string("owned"), .string("source")]))
    scope.finiteTextSource = nil
    scope.preparedCustomSections = ["e\u{301}", "a|b", ""]
    let prepared = try XCTUnwrap(WebsiteTestSettingsShare.customText(in: scope)?.importFields)
    XCTAssertEqual(prepared["text"], .array([.string("e\u{301}"), .string("a|b"), .string("")]))
  }

  func testWholeProfileNativeSelectionKeepsOwnedQuoteWithoutAttachingLegacySettings() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"minWpm":"off","minWpmCustomSpeed":1e999}"#, pointsPerRem: 16, context: .init())
    let configuration = draft.inputRules.applying(to: TestConfiguration(mode: .quote,
      duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()))
    let quote = OfflineQuote(id: "owned-share", title: "Owned", text: "own quote", language: .english, length: .short)
    let selected = WebsiteTestSettingsShare.nativeSelection(configuration: configuration, scope: .init(), quote: quote)
    var oldMixedOwner = selected
    oldMixedOwner.settingsSnapshot = .init()
    XCTAssertThrowsError(try TestConfigurationShare.link(for: oldMixedOwner))
    XCTAssertEqual(selected.quoteID, quote.id)
    XCTAssertNil(selected.settingsSnapshot)
    XCTAssertNil(selected.activeResultTags)
    XCTAssertNil(selected.settingGroups)
    XCTAssertEqual(try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: selected)), selected)
    let cleared = WebsiteTestSettingsShare.nativeSelection(configuration: configuration, scope: .init(), quote: nil)
    XCTAssertNil(cleared.quoteID)
  }

  func testUnrepresentablePreparedSectionsRemainInWebsitePayloadAndRefuseLossyNativeLink() throws {
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.preparedCustomSections = ["a|b", "", "e\u{301}"]
    scope.customCompletion = .sections; scope.customPipeDelimiter = true
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .sections,
      customTextSectionLimit: 3, customTextPipeDelimiter: true)
    let selected = WebsiteTestSettingsShare.nativeSelection(configuration: configuration, scope: scope, quote: nil)
    XCTAssertThrowsError(try TestConfigurationShare.link(for: selected))
    let custom = try XCTUnwrap(WebsiteTestSettingsShare.customText(in: scope)?.importFields)
    let pieces = WebsiteConfigValue.array([.string("a|b"), .string(""), .string("e\u{301}")])
    XCTAssertEqual(custom["text"], pieces)
    let url = try WebsiteTestSettingsShare.link(.init(runtime: ["mode": .string("custom")], customText: .object(custom)),
      selected: [.mode, .customText])
    let token = try XCTUnwrap(URLComponents(string: url)?.queryItems?.first?.value)
    guard case .array(let tuple) = try WebsiteConfigJSONReader.read(XCTUnwrap(URICompressedPayload.decompress(token))) else {
      return XCTFail("Expected eight slots")
    }
    XCTAssertEqual(tuple[2].importFields?["text"], pieces)
  }

  func testNativeEightSlotActionsApplyOnlySelectedFieldsThroughRealLegacySettingsCommit() throws {
    let suite = "typebar.eight-slot.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let center = LocalNoticeCenter()
    defer { defaults.removePersistentDomain(forName: suite); center.clearAll() }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    settings.strictSpace = true; settings.activeResultTags = ["owned"]
    let before = settings.snapshot
    let current = SavedTestPreset(configuration: .words(25, rules: settings.inputRules, language: .german))
    let link = try WebsiteTestSettingsShare.link(.init(runtime: ["mode": .string("words"),
      "words": .number(17), "language": .string("english_1k")]), selected: [.mode, .parameter, .language])
    XCTAssertEqual(URLComponents(string: link)?.scheme, "typebar")
    var received: SavedTestPreset?
    let result = TestConfigurationShareActions.apply(link, current: current, challenges: [], notices: center,
      applyPreset: { value in
        guard PresetSettingsApplication.commit(original: value, resolved: value,
          configuration: value.configuration, to: settings, appliesGlobalSettings: true) else { return nil }
        received = value; return value
      }, loadChallenge: { _ in XCTFail("No challenge dispatch"); return .rejected })
    XCTAssertEqual(result.outcome, .applied)
    XCTAssertEqual(received?.configuration.wordLimit, 17)
    XCTAssertEqual(received?.configuration.language, .english1k)
    XCTAssertEqual(received?.configuration.rules, current.configuration.rules)
    XCTAssertEqual(settings.snapshot, before)
    XCTAssertNil(received?.settingsSnapshot)
    let successes = center.history.filter { $0.level == .success }
    XCTAssertEqual(successes.count, 1)
    XCTAssertFalse(successes.contains { $0.message.contains("最低") })
    var calls = 0
    for bad in [link + "&preset=x", link + "&testSettings=x", link + "#fragment",
      link.replacingOccurrences(of: "typebar://test?", with: "typebar://test/path?"),
      link.replacingOccurrences(of: "typebar://test?", with: "typebar://user@test?")] {
      let rejected = TestConfigurationShareActions.apply(bad, current: current, challenges: [], notices: center,
        applyPreset: { calls += 1; return $0 }, loadChallenge: { _ in .rejected })
      XCTAssertEqual(rejected.outcome, .rejected)
    }
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(settings.snapshot, before)
  }

  func testIncomingNativeLinksHaveOneLatestPendingDeliveryAndNeverApplyOnReceipt() throws {
    let inbox = TestSettingsLinkInbox()
    func link(_ count: Int) throws -> URL {
      try XCTUnwrap(URL(string: WebsiteTestSettingsShare.link(.init(runtime: ["mode": .string("words"),
        "words": .number(Double(count))]), selected: [.mode, .parameter])))
    }
    let first = try link(17), second = try link(23), third = try link(29)
    XCTAssertTrue(inbox.receive(first, allowed: false))
    XCTAssertNil(inbox.presented)
    XCTAssertTrue(inbox.receive(second, allowed: false))
    XCTAssertEqual(inbox.pending?.link, second.absoluteString)
    inbox.presentNext(allowed: true)
    let identity = try XCTUnwrap(inbox.presented?.id)
    XCTAssertEqual(inbox.presented?.link, second.absoluteString)
    XCTAssertNil(inbox.pending)
    XCTAssertTrue(inbox.receive(second, allowed: true))
    XCTAssertEqual(inbox.presented?.id, identity)
    XCTAssertTrue(inbox.receive(third, allowed: true))
    XCTAssertEqual(inbox.presented?.id, identity)
    XCTAssertEqual(inbox.pending?.link, third.absoluteString)
    inbox.presented = nil; inbox.presentNext(allowed: false)
    XCTAssertNil(inbox.presented)
    inbox.presentNext(allowed: true)
    XCTAssertEqual(inbox.presented?.link, third.absoluteString)
    XCTAssertFalse(inbox.receive(try XCTUnwrap(URL(string: "typebar://profile?id=owned")), allowed: true))
    XCTAssertFalse(inbox.receive(try XCTUnwrap(URL(string: "https://owned.invalid?testSettings=x")), allowed: true))
  }

  func testIncomingLinkPrefillsProductionPanelWithoutApplyingOrShowingWindow() throws {
    let center = LocalNoticeCenter()
    defer { center.clearAll() }
    let incoming = try WebsiteTestSettingsShare.link(.init(runtime: ["mode": .string("words"),
      "words": .number(17)]), selected: [.mode, .parameter])
    var calls = 0
    let host = NSHostingView(rootView: TestConfigurationShareView(currentPreset: .init(configuration: .words(25)),
      initialPastedLink: incoming, notices: center, onApply: { calls += 1; return $0 }))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 560, height: 380),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    func fields(_ view: NSView) -> [String] {
      var values: [String] = []
      if let text = view as? NSTextView { values.append(text.string) }
      if let field = view as? NSTextField { values.append(field.stringValue) }
      return values + view.subviews.flatMap(fields)
    }
    XCTAssertTrue(fields(host).contains { $0.utf8.elementsEqual(incoming.utf8) })
    XCTAssertEqual(calls, 0)
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(center.history.contains { $0.level == .success })
  }

  private struct Output: Decodable {
    struct Fixture: Decodable { let mask: Int, runtimeJSON: String, customJSON: String, quoteID: Int, tupleJSON: String }
    struct Compression: Decodable { let text: String, compressed: String }
    struct Emoji: Decodable { let customJSON: String, tupleJSON: String }
    let fixtures: [Fixture]
    let compression: [Compression]
    let emoji: Emoji
  }
  private func oracle() throws -> Output {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires the fixed reference and pinned config-link dependencies")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-test-settings-share.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data)
  }
}
