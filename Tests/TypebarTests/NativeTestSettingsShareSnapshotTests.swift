import XCTest
@testable import Typebar

@MainActor final class NativeTestSettingsShareSnapshotTests: XCTestCase {
  private func tuple(_ snapshot: WebsiteTestSettingsShare.Snapshot,
    _ fields: Set<WebsiteTestSettingsShare.Field>) throws -> WebsiteConfigValue {
    let link = try WebsiteTestSettingsShare.link(snapshot, selected: fields)
    let json = try XCTUnwrap(WebsiteSharedLinkImport.json(from: link))
    return try WebsiteConfigJSONReader.read(json)
  }

  func testNativeWindowCapturesSelectionAndIndependentCustomText() throws {
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.parameterMemory = .init(duration: 45, wordLimit: 50, customTextDuration: 60,
      customTextWordLimit: 30, customTextSectionLimit: 7)
    scope.customText = "owned alpha|字😀"; scope.customCompletion = .sections
    scope.customOrdering = .shuffled; scope.customPipeDelimiter = true
    var config = TestConfiguration.words(17, language: .spanish).with(modifiers: [.noSpaces, .noQuit])
    config.difficulty = .expert
    let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: scope)
    XCTAssertEqual(snapshot.runtime["mode"], .string("words"))
    XCTAssertEqual(snapshot.runtime["words"], .number(17))
    XCTAssertEqual(snapshot.runtime["time"], .number(45))
    XCTAssertEqual(snapshot.runtime["language"], .string("spanish"))
    XCTAssertEqual(snapshot.runtime["difficulty"], .string("expert"))
    XCTAssertEqual(snapshot.runtime["funbox"], .array([.string("nospace"), .string("no_quit")]))
    XCTAssertEqual(snapshot.runtime["punctuation"], .bool(false))
    XCTAssertEqual(snapshot.runtime["numbers"], .bool(false))
    let custom = try XCTUnwrap(snapshot.customText)
    XCTAssertEqual(custom, WebsiteTestSettingsShare.customText(in: scope))
    XCTAssertEqual(custom.importFields?["text"], .array([.string("owned alpha"), .string("字😀")]))
    XCTAssertFalse(snapshot.hasUnmappedQuote)
    XCTAssertTrue(snapshot.unavailableFields.isEmpty)
  }

  func testNativeEditorDoesNotInheritAnotherProfilesRawCustomRecord() throws {
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.customText = "owned native editor"
    scope.websiteCustomText = try .init(value: .object(["text": .array([.string("foreign profile")]),
      "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(1)]),
      "pipeDelimiter": .bool(false)]))
    let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: .words(7), scope: scope)
    XCTAssertEqual(snapshot.customText?.importFields?["text"],
      .array([.string("owned"), .string("native"), .string("editor")]))
  }

  func testEveryAuditedLanguageAndOfficialFunboxCapturesItsExactIdentity() throws {
    for (name, language) in WebsiteLanguageIdentity.byWebsiteName {
      let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: .words(7, language: language), scope: .init())
      XCTAssertEqual(snapshot.runtime["language"], .string(name))
    }
    for name in FunboxCommandCatalog.officialNames {
      let target = try XCTUnwrap(FunboxCommandCatalog.target(for: "funbox.changeFunbox" + name))
      var config = TestConfiguration.words(7)
      switch target {
      case .modifier(let value): config = config.with(modifiers: [value])
      case .polyglot: config.language = .mixedLanguages; config = config.with(polyglotBaseLanguage: .spanish)
      case .clear: return XCTFail("Clear is not an active funbox")
      }
      let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: .init())
      XCTAssertEqual(snapshot.runtime["funbox"], .array([.string(name)]), name)
      XCTAssertTrue(snapshot.unavailableFields.isEmpty, name)
    }
  }

  func testOrderedTransformsAndUnsharedLazyStateAreNotFlattened() throws {
    var config = TestConfiguration.words(7).with(modifiers: [.doubleCharacters, .rot13, .noQuit, .lazyLatin])
    config.websiteTextAlterationOrder = [.rot13, .doubleCharacters]
    let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: .init())
    XCTAssertEqual(snapshot.runtime["funbox"], .array([.string("rot13"), .string("ddoouubblleedd"), .string("no_quit")]))
    XCTAssertTrue(snapshot.unavailableFields.isEmpty)
    config.websiteTextAlterationOrder = [.rot13]
    let invalid = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: .init())
    XCTAssertEqual(invalid.unavailableFields, [.funbox])
    XCTAssertThrowsError(try tuple(invalid, [.funbox]))
    XCTAssertNoThrow(try tuple(invalid, [.mode, .parameter]))
  }

  func testNativeOnlyRulesAndOwnedQuoteIDsAreNeverMisrepresentedAsWebsiteFields() throws {
    let native = WebsiteTestSettingsShare.nativeSnapshot(configuration: .words(7).with(modifiers: [.correctBeforeAdvance]), scope: .init())
    XCTAssertEqual(native.unavailableFields, [.funbox]); XCTAssertNil(native.runtime["funbox"])
    XCTAssertThrowsError(try tuple(native, [.funbox]))
    XCTAssertNoThrow(try tuple(native, [.mode, .parameter]))
    let quote = WebsiteTestSettingsShare.nativeSnapshot(configuration:
      .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()), scope: .init())
    XCTAssertTrue(quote.hasUnmappedQuote)
    XCTAssertThrowsError(try tuple(quote, [.mode, .parameter]))
    XCTAssertNoThrow(try tuple(quote, [.mode, .language]))
    let large = WebsiteTestSettingsShare.nativeSnapshot(configuration: .words(Int.max), scope: .init())
    XCTAssertTrue(large.unavailableFields.contains(.parameter))
    XCTAssertThrowsError(try tuple(large, [.mode, .parameter]))
    XCTAssertNoThrow(try tuple(large, [.mode]))
  }

  func testNativeSelectedLinkCanRoundTripThroughExistingNativeReceiver() throws {
    let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration:
      .words(17, language: .spanish).with(modifiers: [.noSpaces, .noQuit]), scope: .init())
    let fields: Set<WebsiteTestSettingsShare.Field> = [.mode, .parameter, .language, .funbox]
    let link = try WebsiteTestSettingsShare.link(snapshot, selected: fields)
    let current = SavedTestPreset(configuration: .words(5, rules: .init(strictSpace: true)))
    let received = try LegacyTestSettingsLinkImporter.preset(from: link, current: current)
    XCTAssertEqual(received.configuration.mode, .words)
    XCTAssertEqual(received.configuration.wordLimit, 17)
    XCTAssertEqual(received.configuration.language, .spanish)
    XCTAssertEqual(received.configuration.rules, current.configuration.rules)
    XCTAssertTrue(received.configuration.modifiers.contains(.noSpaces))
    XCTAssertTrue(received.configuration.modifiers.contains(.noQuit))
  }

  func testTimeParametersThatSourceIntegerPrefixWouldChangeAreNotSharedLossily() throws {
    for duration in [0.5, 2.5, 1e21, Double.greatestFiniteMagnitude] {
      var config = TestConfiguration.words(7)
      config.mode = .time; config.wordLimit = nil; config.duration = duration
      let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: .init())
      XCTAssertTrue(snapshot.unavailableFields.contains(.parameter), "\(duration)")
      XCTAssertThrowsError(try tuple(snapshot, [.mode, .parameter]))
      XCTAssertNoThrow(try tuple(snapshot, [.mode]))
    }
  }

  private func receive(_ snapshot: WebsiteTestSettingsShare.Snapshot,
    fields: Set<WebsiteTestSettingsShare.Field>) throws -> WebsiteSharedSettingsReceiver.Outcome {
    let defaults = try WebsiteConfigNativeProfile.defaultDocument().values
    let custom = try WebsiteCustomTextSettings(value: .object(["text": .array([.string("own")]),
      "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(1)]),
      "pipeDelimiter": .bool(false)]))
    return WebsiteSharedSettingsReceiver.receive(json: WebsiteConfigJSONWriter.write(try tuple(snapshot, fields)),
      current: .init(runtime: defaults, settingsStore: defaults, custom: custom, active: false))
  }

  func testAcceptedTimeNumbersSurviveSourceReceiverIntegerParsing() throws {
    for duration in [0, 1, 42, 1e20] {
      var config = TestConfiguration.words(7)
      config.mode = .time; config.wordLimit = nil; config.duration = duration
      let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: .init())
      XCTAssertTrue(snapshot.unavailableFields.isEmpty)
      let outcome = try receive(snapshot, fields: [.mode, .parameter])
      XCTAssertFalse(outcome.parseRejected); XCTAssertFalse(outcome.threw)
      XCTAssertEqual(outcome.state.runtime["time"], .number(duration))
    }
  }

  func testIndependentCustomTimeFractionSurvivesWithoutIntegerCoercion() throws {
    var scope = WebsiteConfigSessionBuilder.Scope()
    scope.customText = "own words"; scope.customCompletion = .time; scope.customDurationOverride = 2.5
    let config = TestConfiguration(mode: .custom, duration: 2.5, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time)
    let snapshot = WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: scope)
    XCTAssertTrue(snapshot.unavailableFields.isEmpty)
    let outcome = try receive(snapshot, fields: [.mode, .customText])
    XCTAssertFalse(outcome.parseRejected); XCTAssertFalse(outcome.threw)
    XCTAssertEqual(outcome.state.custom.limitMode, "time")
    XCTAssertEqual(outcome.state.custom.limitValue, 2.5)
  }

  func testNativePageCaptureAndCopyReadLatestValuesWithoutPublishingOrSaving() throws {
    var config = TestConfiguration.words(7)
    var scope = WebsiteConfigSessionBuilder.Scope(); scope.customText = "owned spare"
    var session = TypingSession(configuration: config, prompt: "own text")
    session.insertBatch("o")
    let page = PracticePageSessionState(session: session)
    let before = page.session.generationState
    let notices = LocalNoticeCenter(); defer { notices.clearAll() }
    var writes: [String] = []
    let controller = WebsiteTestSettingsShareController(read: {
      WebsiteTestSettingsShare.pageSnapshot(page) { WebsiteTestSettingsShare.nativeSnapshot(configuration: config, scope: scope) }
    }, notices: notices, write: { writes.append($0); return true })
    XCTAssertTrue(controller.selected.isEmpty)
    controller.selected = [.mode, .parameter]
    config.mode = .time; config.wordLimit = nil; config.duration = 42
    controller.copy()
    let raw = try XCTUnwrap(WebsiteSharedLinkImport.json(from: try XCTUnwrap(writes.last)))
    XCTAssertEqual(try WebsiteConfigJSONReader.read(raw),
      .array([.string("time"), .string("42"), .null, .null, .null, .null, .null, .null]))
    XCTAssertEqual(page.session.generationState, before)
    XCTAssertNil(page.presentation); XCTAssertNil(page.practice)
    scope.customTextRecoveryBlocked = true
    XCTAssertNil(controller.snapshot?.customText)
    XCTAssertNotNil(controller.link)
    controller.selected = [.mode, .funbox]
    config = config.with(modifiers: [.correctBeforeAdvance])
    XCTAssertFalse(controller.isEnabled(.funbox))
    XCTAssertNil(controller.link); XCTAssertNotNil(controller.failureMessage)
    let count = writes.count
    controller.copy(); XCTAssertEqual(writes.count, count)
    controller.selected.remove(.funbox)
    XCTAssertNotNil(controller.link)
  }

  func testNativeSnapshotsAgainstCompletePinnedURLProducerForEverySelectionMask() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires complete pinned share producer and compression library")
    }
    var scope = WebsiteConfigSessionBuilder.Scope(); scope.customText = "own text 字😀"
    var configurations: [TestConfiguration] = [.words(17), .words(0)]
    var timed = TestConfiguration.words(17); timed.mode = .time; timed.wordLimit = nil; timed.duration = 42
    configurations.append(timed)
    for mode in [TestMode.custom, .zen, .quote] {
      configurations.append(.init(mode: mode, duration: nil, wordLimit: nil, difficulty: .expert, rules: .init()))
    }
    var mixed = TestConfiguration.words(7); mixed.language = .mixedLanguages
    mixed = mixed.with(polyglotBaseLanguage: .spanish); configurations.append(mixed)
    configurations.append(.words(7).with(modifiers: [.noSpaces, .noQuit]))
    let snapshots = configurations.map { configuration in
      var customScope = scope
      if configuration.mode == .custom {
        customScope.customCompletion = .time; customScope.customDurationOverride = 2.5
      }
      return WebsiteTestSettingsShare.nativeSnapshot(configuration: configuration, scope: customScope)
    }
    let payload = WebsiteConfigJSONWriter.write(.array(snapshots.map {
      .object(["runtime": .object($0.runtime), "custom": $0.customText ?? .null])
    }), asciiOnly: false)
    struct Output: Decodable {
      struct Fixture: Decodable { let capture: Int, mask: Int, tupleJSON: String }
      let fixtures: [Fixture]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-test-settings-share.mjs").path,
      reference, "--native-captures"]
    process.standardInput = input; process.standardOutput = output
    try process.run(); input.fileHandleForWriting.write(Data(payload.utf8)); input.fileHandleForWriting.closeFile()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { return XCTFail("Pinned producer failed") }
    let fixtures = try JSONDecoder().decode(Output.self, from: bytes).fixtures
    XCTAssertEqual(fixtures.count, 1920)
    for fixture in fixtures {
      let fields = Set(WebsiteTestSettingsShare.Field.allCases.filter { fixture.mask & (1 << $0.rawValue) != 0 })
      XCTAssertEqual(try tuple(snapshots[fixture.capture], fields), try WebsiteConfigJSONReader.read(fixture.tupleJSON))
    }
  }
}
