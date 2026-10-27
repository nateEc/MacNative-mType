import XCTest
@testable import Typebar

@MainActor final class WebsiteCustomTextStateTests: XCTestCase {
  private func custom(_ mode: String = "word", _ count: Double = 3.5,
    text: [WebsiteConfigValue] = [.string("aa"), .string("bb")], pipe: Bool = false) throws -> WebsiteCustomTextSettings {
    try .init(value: .object(["text": .array(text), "mode": .string("repeat"),
      "limit": .object(["mode": .string(mode), "value": .number(count)]), "pipeDelimiter": .bool(pipe)]))
  }

  func testColdReadRetainsRawCodeUnitsAndFractionalInfiniteAndSignedZeroLimits() throws {
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    for count in [3.5, .infinity, -0.0] {
      let value = try custom("section", count, text: [.string(""), .string("a|b"), .string(units: [0xd800]),
        .string("e\u{301}"), .string("é"), .string("字😀")], pipe: true)
      XCTAssertTrue(WebsiteCustomTextStateStore(defaults: defaults).save(value))
      let reopened = try XCTUnwrap(WebsiteCustomTextStateStore(defaults: defaults).read().settings)
      XCTAssertEqual(reopened.value, value.value)
      XCTAssertEqual(reopened.limitValue.bitPattern, count.bitPattern)
    }
  }

  func testOpaqueOrForeignRecordIsNotOverwritten() throws {
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    for opaque in [Data("future-record".utf8), Data([0xff, 0x00])] {
      defaults.set(opaque, forKey: WebsiteCustomTextStateStore.storageKey)
      let store = WebsiteCustomTextStateStore(defaults: defaults)
      XCTAssertEqual(store.read(), .unavailable)
      XCTAssertFalse(store.save(try custom()))
      XCTAssertEqual(defaults.data(forKey: WebsiteCustomTextStateStore.storageKey), opaque)
    }
  }

  func testPublishedWindowAndShareRetainRawCustomSettingsAcrossOrdinaryMode() throws {
    let value = try custom("section", .infinity, text: [.string(""), .string("a|b"), .string(units: [0xd800])], pipe: true)
    let scope = WebsiteConfigSessionBuilder.Scope(websiteCustomText: value)
    let window = WebsiteConfigPracticeScopeSource.Window.published(owner: UUID(), revision: UUID(), scope: scope)
    XCTAssertEqual(WebsiteTestSettingsShare.customText(in: scope), value.value)
    guard case .website(let published) = window.custom else { return XCTFail("Published window lost the raw custom owner") }
    XCTAssertEqual(published.value, value.value)
  }

  func testStoredFractionalSourceHydratesAndGeneratesThenSurvivesPublishedWindow() async throws {
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory()), account = AccountSession(defaults: defaults)
    let value = try custom()
    XCTAssertTrue(settings.saveWebsiteCustomTextState(value))
    let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account, pointsPerRem: 16,
      documentComplete: true, development: false)
    let owner = UUID()
    var window = WebsiteConfigPracticeScopeSource.Window(owner: owner, customRecoveryBlocked: false)
    let source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { window })
    defer { source.stop(); environment.stop() }
    let captured = try source.capture(owner: owner, preserving: .init())
    XCTAssertEqual(captured.scope.websiteCustomText, value)
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: captured.scope)
    XCTAssertEqual(ready.session.configuration.wordLimit, 4)
    XCTAssertEqual(ready.session.prompt, "aa bb aa bb")
    XCTAssertNil(WebsiteTestSettingsShare.nativeSelection(configuration: ready.session.configuration,
      scope: ready.scope, quote: nil).customText, "Legacy full link must not silently round 3.5 to 4")
    window = .published(owner: owner, revision: UUID(), scope: ready.scope)
    let next = try source.capture(owner: owner, preserving: ready.scope)
    XCTAssertEqual(next.scope.websiteCustomText, value)
    XCTAssertEqual(WebsiteTestSettingsShare.customText(in: next.scope), value.value)
  }

  func testFractionalSectionAndTimeAndInfiniteLimitsUseNativeStreamsWithoutChangingRawOwner() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    for (mode, number) in [("word", 0.5), ("section", 1.5), ("time", 0.125),
      ("word", Double.infinity), ("section", Double.infinity), ("time", Double.infinity)] {
      let value = try custom(mode, number)
      let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: value))
      XCTAssertEqual(ready.scope.websiteCustomText?.value, value.value)
      XCTAssertEqual(WebsiteTestSettingsShare.customText(in: ready.scope), value.value)
      if mode == "word" { XCTAssertEqual(ready.session.configuration.wordLimit, number.isInfinite ? 0 : 1) }
      if mode == "section" { XCTAssertEqual(ready.session.configuration.customTextSectionLimit, number.isInfinite ? 0 : 2) }
      if mode == "time" { XCTAssertEqual(ready.session.configuration.duration, number.isInfinite ? 0 : number) }
      if number.isInfinite { XCTAssertTrue(ready.session.configuration.isInfinite) }
      if mode == "word", !number.isInfinite { XCTAssertEqual(ready.session.prompt, "aa") }
      if mode == "section", !number.isInfinite { XCTAssertEqual(ready.session.prompt, "aa bb") }
    }
  }

  func testUnpairedSourceIsRetainedForSharingButCannotBecomeReplacementCharacterPractice() async throws {
    let raw = try custom(text: [.string(units: [0xd800])])
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    let scope = raw.applying(to: .init())
    XCTAssertTrue(scope.customTextRecoveryBlocked)
    XCTAssertEqual(WebsiteTestSettingsShare.customText(in: scope), raw.value)
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: scope)
      XCTFail("Cannot replace a source code unit with U+FFFD")
    } catch WebsiteConfigSessionBuildError.customTextUnavailable {}
  }

  func testUnknownVersionAndMalformedUnitsRemainOpaqueAndDoNotEraseLegacySource() throws {
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
    let legacy = CustomTextStateDocument(source: .editor("owned legacy text"),
      configuration: .init(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()))
    XCTAssertTrue(settings.saveCustomTextState(legacy))
    XCTAssertTrue(settings.saveWebsiteCustomTextState(try custom()))
    let bytes = try XCTUnwrap(defaults.data(forKey: WebsiteCustomTextStateStore.storageKey))
    let original = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
    for replacement in [["version": 2], ["text": [Data([0xd8])]], ["limitBits": "7ff8000000000000"]] as [[String: Any]] {
      let mutated = original.merging(replacement) { _, new in new }
      let opaque = try PropertyListSerialization.data(fromPropertyList: mutated, format: .binary, options: 0)
      defaults.set(opaque, forKey: WebsiteCustomTextStateStore.storageKey)
      let generation = settings.websiteCustomTextStateGeneration
      XCTAssertEqual(settings.websiteCustomTextStateRead, .unavailable)
      XCTAssertFalse(settings.saveWebsiteCustomTextState(try custom()))
      XCTAssertEqual(settings.websiteCustomTextStateGeneration, generation)
      XCTAssertEqual(defaults.data(forKey: WebsiteCustomTextStateStore.storageKey), opaque)
      XCTAssertEqual(settings.customTextStateRead, .available(legacy))
    }
  }

  func testCustomStorageGenerationRejectsStaleContentEvenAfterABA() async throws {
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory()), account = AccountSession(defaults: defaults)
    XCTAssertTrue(settings.saveWebsiteCustomTextState(try custom()))
    let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account, pointsPerRem: 16,
      documentComplete: true, development: false)
    let owner = UUID()
    let window = WebsiteConfigPracticeScopeSource.Window(owner: owner, customRecoveryBlocked: false)
    let source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { window })
    defer { source.stop(); environment.stop() }
    let old = try source.capture(owner: owner, preserving: .init())
    XCTAssertTrue(settings.saveWebsiteCustomTextState(try custom("word", 7)))
    XCTAssertTrue(settings.saveWebsiteCustomTextState(try custom()))
    XCTAssertFalse(source.isCurrent(old))
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while environment.read() == nil && ContinuousClock.now < deadline { await Task.yield() }
    let refreshed = try source.capture(owner: owner, preserving: .init())
    XCTAssertEqual(refreshed.scope.websiteCustomText, old.scope.websiteCustomText)
    XCTAssertFalse(source.isCurrent(old))
  }

  func testUnavailableStoredCustomBlocksOnlyCustomGenerationAndLargeSourceRemainsShareable() async throws {
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("future".utf8), forKey: WebsiteCustomTextStateStore.storageKey)
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory()), account = AccountSession(defaults: defaults)
    let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account, pointsPerRem: 16,
      documentComplete: true, development: false)
    let owner = UUID()
    let window = WebsiteConfigPracticeScopeSource.Window(owner: owner, customRecoveryBlocked: false)
    let source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { window })
    defer { source.stop(); environment.stop() }
    let captured = try source.capture(owner: owner, preserving: .init())
    XCTAssertTrue(captured.scope.customTextRecoveryBlocked)
    let words = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":2}"#, pointsPerRem: 16, context: .init())
    let normal = try await WebsiteConfigSessionBuilder.prepare(draft: words, scope: captured.scope)
    XCTAssertFalse(normal.session.prompt.isEmpty)
    let raw = try custom("word", 1e99)
    let large = try await WebsiteConfigSessionBuilder.prepare(draft: words, scope: .init(websiteCustomText: raw))
    XCTAssertEqual(WebsiteTestSettingsShare.customText(in: large.scope), raw.value)
    let customDraft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: customDraft, scope: captured.scope)
      XCTFail("Unknown data cannot fall back to a guessed custom prompt")
    } catch WebsiteConfigSessionBuildError.customTextUnavailable {}
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: customDraft, scope: large.scope)
      XCTFail("Cannot silently clamp a retained source limit")
    } catch WebsiteConfigSessionBuildError.unrepresentableConfiguration {}
  }

  func testCompletePinnedReceiverCustomStatesSurviveNativeStorageAndScope() throws {
    struct Fixture: Decodable { let label: String, custom: String }
    struct Output: Decodable { let fixtures: [Fixture] }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned receiver, real Solid, Zod and LZ preparation")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--shared-test-settings"]
    process.standardOutput = pipe; try process.run()
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: bytes)
    XCTAssertEqual(output.fixtures.count, 1308)
    let suite = "typebar.website-custom.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory()), account = AccountSession(defaults: defaults)
    var seen = Set<String>()
    for f in output.fixtures where seen.insert(f.custom).inserted {
      let expected = try WebsiteConfigJSONReader.read(f.custom), custom = try WebsiteCustomTextSettings(value: expected)
      XCTAssertTrue(settings.saveWebsiteCustomTextState(custom), f.label)
      let reopened = try XCTUnwrap(WebsiteCustomTextStateStore(defaults: defaults).read().settings)
      XCTAssertEqual(reopened.value, expected, f.label)
      XCTAssertEqual(reopened.limitValue.bitPattern, custom.limitValue.bitPattern, f.label)
      let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account, pointsPerRem: 16,
        documentComplete: true, development: false)
      let owner = UUID()
      var window = WebsiteConfigPracticeScopeSource.Window(owner: owner, customRecoveryBlocked: false)
      let source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { window })
      defer { source.stop(); environment.stop() }
      let captured = try source.capture(owner: owner, preserving: .init())
      window = .published(owner: owner, revision: UUID(), scope: captured.scope)
      let published = try source.capture(owner: owner, preserving: captured.scope)
      XCTAssertEqual(published.scope.websiteCustomText?.value, expected, f.label)
      XCTAssertEqual(WebsiteTestSettingsShare.customText(in: published.scope), expected, f.label)
    }
    XCTAssertGreaterThan(seen.count, 6)
  }
}
