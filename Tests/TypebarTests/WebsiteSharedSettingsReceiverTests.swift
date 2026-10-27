import XCTest
@testable import Typebar

@MainActor final class WebsiteSharedSettingsReceiverTests: XCTestCase {
  private struct Output: Decodable { let fixtures: [Fixture] }
  private struct Fixture: Decodable {
    struct Attempt: Decodable { let key: String, json: String, accepted: Bool }
    struct Checkpoint: Decodable { let key: String, json: String }
    let label: String, json: String, active: Bool, initial: String, initialStore: String, initialCustom: String
    let runtime: String, store: String, custom: String, events: String, saves: [String], busy: Bool, activeAfter: Bool
    let configCheckpoints: [Checkpoint], customWrites: [String], requests: [String], starts: Int, inits: Int
    let selectedQuote: Double?, parseRejected: Bool, threw: Bool
    let selectedQuoteText: String?, configWrites: [String], initialSaved: String, saved: String
    let failure: [String: [Int]], failureKind: String, attempts: [Attempt], storageFailures: [String]
  }
  private func state(_ fixture: Fixture) throws -> WebsiteSharedSettingsReceiver.State {
    .init(runtime: try XCTUnwrap(WebsiteConfigJSONReader.read(fixture.initial).importFields),
      settingsStore: try XCTUnwrap(WebsiteConfigJSONReader.read(fixture.initialStore).importFields),
      custom: try .init(value: WebsiteConfigJSONReader.read(fixture.initialCustom)), active: fixture.active, restarting: fixture.busy,
      savedConfig: try XCTUnwrap(WebsiteConfigJSONReader.read(fixture.initialSaved).importFields))
  }
  func testSourceWordSelectionChangesRuntimeWithoutSavingConfiguration() throws {
    let f = try XCTUnwrap(oracle().fixtures.first { $0.label == "words-3" })
    let result = WebsiteSharedSettingsReceiver.receive(json: f.json, current: try state(f))
    XCTAssertEqual(result.state.runtime["words"], try WebsiteConfigJSONReader.read(f.runtime).importFields?["words"])
    XCTAssertEqual(result.configSaves.count, f.configCheckpoints.count)
  }

  func testOrderedReceiverAgainstCompletePinnedHandlerSettersStoreAndCustomModule() throws {
    let output = try oracle()
    XCTAssertEqual(output.fixtures.count, 1308)
    for f in output.fixtures {
      let result = WebsiteSharedSettingsReceiver.receive(json: f.json, current: try state(f))
      try assertOutcome(result, matches: f)
    }
  }
  private func assertOutcome(_ result: WebsiteSharedSettingsReceiver.Outcome, matches f: Fixture,
    file: StaticString = #filePath, line: UInt = #line) throws {
      let runtime = try XCTUnwrap(WebsiteConfigJSONReader.read(f.runtime).importFields)
      let store = try XCTUnwrap(WebsiteConfigJSONReader.read(f.store).importFields)
      XCTAssertEqual(result.state.runtime, runtime, f.label)
      XCTAssertEqual(result.state.settingsStore, store, f.label)
      XCTAssertEqual(result.state.custom.value, try WebsiteConfigJSONReader.read(f.custom), f.label)
      let events = try JSONDecoder().decode([WebsiteConfigApplicationEvent].self, from: Data(f.events.utf8))
      XCTAssertEqual(result.events, events, f.label)
      XCTAssertEqual(result.configSaves.map(\.key), f.saves, f.label)
      XCTAssertEqual(result.configSaves.count, f.configCheckpoints.count, f.label)
      for (actual, expected) in zip(result.configSaves, f.configCheckpoints) {
        XCTAssertEqual(actual.key, expected.key, f.label)
        XCTAssertEqual(actual.runtime, try WebsiteConfigJSONReader.read(expected.json).importFields, f.label)
      }
      XCTAssertEqual(try result.customWrites.map { try WebsiteConfigJSONReader.read($0) },
        try f.customWrites.map { try WebsiteConfigJSONReader.read($0) }, f.label)
      XCTAssertEqual(try result.configWrites.map { try WebsiteConfigJSONReader.read($0) },
        try f.configWrites.map { try WebsiteConfigJSONReader.read($0) }, f.label)
      XCTAssertEqual(result.state.savedConfig, try WebsiteConfigJSONReader.read(f.saved).importFields, f.label)
      XCTAssertEqual(result.restartRequests, f.requests, f.label)
      XCTAssertEqual(result.restartStarts, f.starts, f.label)
      XCTAssertEqual(f.starts, f.inits, "Actual restart must stop at exactly one owned initializer per admission")
      XCTAssertEqual(result.parseRejected, f.parseRejected, f.label)
      XCTAssertEqual(result.threw, f.threw, f.label)
      let quote: WebsiteConfigValue?
      if let text = f.selectedQuoteText {
        quote = .number(text == "NaN" ? .nan : text == "1e999" ? .infinity : text == "-1e999" ? -.infinity : try XCTUnwrap(Double(text)))
      } else { quote = nil }
      XCTAssertEqual(result.state.selectedQuote, quote, f.label)
      XCTAssertEqual(result.state.active, f.activeAfter, f.label)
      XCTAssertEqual(result.storageFailures, f.storageFailures, f.label, file: file, line: line)
      XCTAssertEqual(result.storageAttempts.count, f.attempts.count, f.label, file: file, line: line)
      for (actual, expected) in zip(result.storageAttempts, f.attempts) {
        XCTAssertEqual(actual.key, expected.key, f.label, file: file, line: line)
        XCTAssertEqual(actual.accepted, expected.accepted, f.label, file: file, line: line)
        XCTAssertEqual(try WebsiteConfigJSONReader.read(actual.json), try WebsiteConfigJSONReader.read(expected.json), f.label, file: file, line: line)
      }
  }
  func testStorageFailuresAgainstPinnedReceiverAndActualStorageModule() throws {
    let output = try oracle(storageFailures: true)
    XCTAssertEqual(output.fixtures.count, 18)
    for f in output.fixtures {
      var counts: [String: Int] = [:]
      func accept(_ key: String) throws -> Bool {
        let count = (counts[key] ?? 0) + 1; counts[key] = count
        if f.failure[key]?.contains(-1) == true || f.failure[key]?.contains(count) == true {
          if f.failureKind == "generic" { throw StorageError.rejected }; return false
        }
        return true
      }
      let result = WebsiteSharedSettingsReceiver.receive(json: f.json, current: try state(f), storage: .init(
        writeCustom: { _ in try accept("customTextSettings") }, writeConfiguration: { _ in try accept("config") }))
      try assertOutcome(result, matches: f)
      XCTAssertEqual(counts.values.reduce(0, +), f.attempts.count, f.label)
    }
  }
  private enum StorageError: Error { case rejected }
  func testReceivedDraftPreservesPinnedSnapshotsWithoutReplayingLanguageListeners() throws {
    let output = try oracle()
    XCTAssertEqual(output.fixtures.count, 1308)
    for f in output.fixtures {
      let outcome = WebsiteSharedSettingsReceiver.receive(json: f.json, current: try state(f))
      if outcome.parseRejected {
        XCTAssertThrowsError(try WebsiteConfigNativeDraft(received: outcome, pointsPerRem: 16), f.label); continue
      }
      let draft = try WebsiteConfigNativeDraft(received: outcome, pointsPerRem: 16)
      XCTAssertNil(draft.prepared, "Receipt is not a full import")
      XCTAssertEqual(draft.projection.runtime, try WebsiteConfigJSONReader.read(f.runtime).importFields, f.label)
      XCTAssertEqual(draft.settingsStoreValues, try WebsiteConfigJSONReader.read(f.store).importFields, f.label)
      let applied = try WebsiteConfigLazyModeLifecycle.applyingEvents(draft, pointsPerRem: 16)
      XCTAssertEqual(applied.projection.events, outcome.events, f.label)
      XCTAssertEqual(applied.projection.runtime, draft.projection.runtime, f.label)
      XCTAssertEqual(applied.settingsStoreValues, draft.settingsStoreValues, f.label)
    }
  }
  func testReceiverBindsActualNativeStoresWithoutPromotingNosaveOrOverwritingOpaqueData() throws {
    let fixtures = try oracle(storageFailures: true).fixtures
    for (label, policy) in [("custom-failure-quota-2", "second-custom"),
      ("config-failure-quota", "stale-file"), ("custom-failure-quota--1", "opaque-custom")] {
      let f = try XCTUnwrap(fixtures.first { $0.label == label }), current = try state(f)
      let suite = "typebar.receiver-storage.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-receiver-storage-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
      let register = WebsiteConfigFileRegister(directory: directory)
      guard case .committed(let initial) = try register.commit(runtime: XCTUnwrap(current.savedConfig),
        lazyMemory: current.lazyMemory, replacing: XCTUnwrap(register.read().revision)) else { return XCTFail("Initial record failed") }
      var revision = initial
      XCTAssertTrue(settings.saveWebsiteCustomTextState(current.custom))
      let generation = settings.websiteCustomTextStateGeneration
      let opaque = Data("future custom source, keep intact".utf8)
      var external: [String: WebsiteConfigValue]?
      if policy == "opaque-custom" { defaults.set(opaque, forKey: WebsiteCustomTextStateStore.storageKey) }
      if policy == "stale-file" {
        var newer = try XCTUnwrap(current.savedConfig); newer["words"] = .number(29)
        guard case .committed = try register.commit(runtime: newer, lazyMemory: current.lazyMemory, replacing: revision)
          else { return XCTFail("Competing update failed") }
        external = newer
      }
      var customCalls = 0
      let result = WebsiteSharedSettingsReceiver.receive(json: f.json, current: current, storage: .init(
        writeCustom: { proposed in
          customCalls += 1
          if policy == "second-custom", customCalls == 2 { return false }
          return settings.saveWebsiteCustomTextState(proposed)
        }, writeConfiguration: { proposed in
          switch try register.commit(runtime: proposed.runtime, lazyMemory: current.lazyMemory, replacing: revision) {
          case .committed(let next): revision = next; return true
          case .conflict, .unavailable: return false
          }
        }))
      try assertOutcome(result, matches: f)
      XCTAssertEqual(settings.websiteCustomTextStateGeneration - generation,
        UInt64(result.storageAttempts.filter { $0.key == "customTextSettings" && $0.accepted }.count), label)
      if policy == "opaque-custom" {
        XCTAssertEqual(settings.websiteCustomTextStateRead, .unavailable)
        XCTAssertEqual(defaults.data(forKey: WebsiteCustomTextStateStore.storageKey), opaque)
      } else { XCTAssertEqual(settings.websiteCustomTextStateRead.settings?.value, result.state.custom.value, label) }
      guard case .available(let stored) = try register.read().state else { return XCTFail("Saved configuration was lost") }
      XCTAssertEqual(stored, external ?? result.state.savedConfig, label)
      XCTAssertNotEqual(stored["language"], result.state.runtime["language"], "Later nosave language must not be promoted")
      XCTAssertNotEqual(stored["lazyMode"], result.state.runtime["lazyMode"], "Arabic listener is also temporary")
    }
  }
  private func oracle(storageFailures: Bool = false) throws -> Output {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned source, real Solid, Zod and LZ preparation")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--shared-test-settings"]
    if storageFailures { process.arguments?.append("--storage-failures") }
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data)
  }
}
