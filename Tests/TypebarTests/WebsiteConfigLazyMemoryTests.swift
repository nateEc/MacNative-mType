import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigLazyMemoryTests: XCTestCase {
  @MainActor private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-lazy-memory-\(UUID())")
    let router = PreferenceConfigurationSaveRouter(), owner = UUID()
    let register: WebsiteConfigFileRegister
    let coordinator: WebsiteConfigCommitCoordinator
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("No legacy preference write") })
      let epoch = UUID()
      coordinator = .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
    func write(_ memory: WebsiteConfigLazyModeMemory) throws -> WebsiteConfigFileRegister.Revision {
      var draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4}"#, pointsPerRem: 16, context: .init())
      draft.lazyMemory = memory
      guard case .committed(let revision) = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
        throw WebsiteConfigImportWorkflowError.conflict
      }
      return revision
    }
  }

  func testAllMemoryValuesRoundTripInTheSameRecordAndMemoryOnlyChangesRetireOldCAS() throws {
    let f = try Fixture(); defer { f.close() }
    var previous: WebsiteConfigFileRegister.Revision?
    for remember in [false, true] {
      for arabic in [false, true] {
        let memory = WebsiteConfigLazyModeMemory(remember: remember, prefersArabic: arabic)
        let revision = try f.write(memory)
        let snapshot = try f.register.read()
        let bytes = try Data(contentsOf: f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename))
        guard case .array(let frame) = try WebsiteConfigJSONReader.read(String(decoding: bytes, as: UTF8.self)) else {
          return XCTFail("Missing record frame")
        }
        XCTAssertEqual(frame[4], .array([.bool(remember), .bool(arabic)]), "Version 2 memory tuple order is a wire contract")
        XCTAssertEqual(snapshot.lazyMemory, memory)
        XCTAssertEqual(snapshot.revision, revision)
        var draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4}"#, pointsPerRem: 16, context: .init())
        draft.lazyMemory = memory
        if let previous { XCTAssertEqual(try f.register.commit(draft, replacing: previous), .conflict) }
        XCTAssertEqual(try f.register.commit(draft, replacing: revision, preservingUnchanged: true), .committed(revision))
        draft.lazyMemory.remember.toggle()
        guard case .committed(let changed) = try f.register.commit(draft, replacing: revision, preservingUnchanged: true) else {
          return XCTFail("Memory-only change was ignored")
        }
        XCTAssertNotEqual(changed, revision)
        previous = revision
      }
    }
  }

  func testLegacyRecordDefaultsAreReadableWithoutRewritingAndNextExplicitCommitUpgrades() throws {
    let f = try Fixture(); defer { f.close() }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4}"#, pointsPerRem: 16, context: .init())
    let payload = try WebsiteConfigNativeStateCodec.encode(draft.projection.runtime)
    let legacy = Data(WebsiteConfigJSONWriter.write(.array([
      .string("typebar.website-config-register"), .number(1), .string(UUID().uuidString), .string(payload.base64EncodedString())])).utf8)
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    try legacy.write(to: path); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    let read = try f.register.read()
    XCTAssertEqual(read.state, .available(draft.projection.runtime))
    XCTAssertEqual(read.lazyMemory, .init())
    let revision = try XCTUnwrap(read.revision)
    XCTAssertEqual(try f.register.commit(draft, replacing: revision, preservingUnchanged: true), .committed(revision))
    XCTAssertEqual(try Data(contentsOf: path), legacy)
    guard case .committed = try f.register.commit(draft, replacing: revision) else { return XCTFail("Upgrade failed") }
    guard case .array(let parts) = try WebsiteConfigJSONReader.read(String(decoding: Data(contentsOf: path), as: UTF8.self)) else {
      return XCTFail("Missing record frame")
    }
    XCTAssertEqual(parts[1], .number(2)); XCTAssertEqual(parts.count, 5)
    XCTAssertEqual(try f.register.read().state, read.state)
  }

  func testUnknownOrMalformedMemoryCannotBeRepairedOrOverwritten() throws {
    let f = try Fixture(); defer { f.close() }
    let revision = try f.write(.init(remember: true, prefersArabic: false))
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    guard case .array(let original) = try WebsiteConfigJSONReader.read(String(decoding: Data(contentsOf: path), as: UTF8.self)) else {
      return XCTFail("Missing record")
    }
    var future = original; future[1] = .number(3)
    var legacyWithExtra = original; legacyWithExtra[1] = .number(1)
    let invalidMemories: [WebsiteConfigValue] = [.null, .array([]), .array([.bool(true)]),
      .array([.bool(false), .number(1)]), .array([.bool(true), .bool(false), .bool(true)])]
    let invalid = [future, legacyWithExtra] + invalidMemories.map { value in
      var copy = original; copy[4] = value; return copy
    }
    let draft = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init())
    for frame in invalid {
      let bytes = Data(WebsiteConfigJSONWriter.write(.array(frame)).utf8); try bytes.write(to: path)
      XCTAssertEqual(try f.register.read().state, .unavailable)
      XCTAssertEqual(try f.register.commit(draft, replacing: revision), .unavailable)
      XCTAssertEqual(try Data(contentsOf: path), bytes)
    }
  }

  func testColdRestoreAndNewImportKeepIndependentMemoryAndSingleEditDoesNotResetIt() throws {
    let f = try Fixture(); defer { f.close() }
    let memory = WebsiteConfigLazyModeMemory(remember: true, prefersArabic: false)
    _ = try f.write(memory)
    guard case .prepared(let restored) = try f.coordinator.prepareRestoration() else { return XCTFail("Restore failed") }
    XCTAssertEqual(restored.draft.lazyMemory, memory)
    let imported = try f.coordinator.prepare(#"{"theme":"dracula","rememberLazyMode":false,"prefersArabicLazyMode":true}"#)
    XCTAssertEqual(imported.draft.lazyMemory, memory, "Website JSON does not own the independent local memory")
    let edited = try WebsiteConfigNativeProfile.editDraft(imported.draft, key: "words", value: .number(9),
      pointsPerRem: 16, context: .init())
    XCTAssertEqual(edited.lazyMemory, memory)
  }

  func testPinnedListenerAndPostActivationGenerationMemoryMatrix() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Operation: Decodable { let key: String; let value: WebsiteConfigValue; let nosave: Bool }
    struct Stage: Decodable {
      let lazy: Bool
      let memory: WebsiteConfigLazyModeMemory
      let events: [WebsiteConfigApplicationEvent]
      let saves: Int
    }
    struct Fixture: Decodable {
      let current: [String: WebsiteConfigValue]
      let before: WebsiteConfigLazyModeMemory
      let operation: Operation?
      let full: Bool?
      let stage: Stage
      let lazy: Bool
      let after: WebsiteConfigLazyModeMemory
      let events: [WebsiteConfigApplicationEvent]
      let saves: Int
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-lazy-mode-memory.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 880)
    for (index, fixture) in fixtures.enumerated() {
      var draft = try WebsiteConfigNativeProfile.prepareDraft(WebsiteConfigJSONWriter.write(.object(fixture.current)),
        pointsPerRem: 16, context: .init())
      draft.lazyMemory = fixture.before
      if let operation = fixture.operation {
        draft = try WebsiteConfigNativeProfile.editDraft(draft, key: operation.key, value: operation.value,
          pointsPerRem: 16, context: .init(), nosave: operation.nosave)
      }
      let replay = fixture.operation != nil || fixture.full == true
      let prefix = replay ? 0 : draft.projection.events.count
      let applied = replay ? try WebsiteConfigLazyModeLifecycle.applyingEvents(draft, pointsPerRem: 16) : draft
      XCTAssertEqual(applied.generators.lazyMode, fixture.stage.lazy, "listener stage \(index)")
      XCTAssertEqual(applied.lazyMemory, fixture.stage.memory, "listener stage \(index)")
      let listenerEvents = Array(applied.projection.events.dropFirst(prefix)).filter {
        fixture.full != true || $0.key == "language" || $0.key == "lazyMode"
      }
      XCTAssertEqual(listenerEvents, fixture.stage.events, "listener stage \(index)")
      let resolved = try WebsiteConfigLazyModeLifecycle.prepare(draft, pointsPerRem: 16,
        replayApplicationEvents: replay)
      let staged = try WebsiteConfigLazyModeLifecycle.prepare(applied, pointsPerRem: 16, replayApplicationEvents: false)
      XCTAssertEqual(WebsiteConfigLazyModeLifecycle.savesConfigurationDuringGeneration(from: applied, to: staged),
        fixture.saves > fixture.stage.saves, "source Config LS save calls \(index)")
      XCTAssertEqual(staged.projection.events, resolved.projection.events, "split and combined event order \(index)")
      XCTAssertEqual(staged.lazyMemory, resolved.lazyMemory, "split and combined memory \(index)")
      XCTAssertEqual(staged.generators.lazyMode, resolved.generators.lazyMode, "split and combined value \(index)")
      XCTAssertEqual(resolved.generators.lazyMode, fixture.lazy, "fixture \(index)")
      XCTAssertEqual(resolved.lazyMemory, fixture.after, "fixture \(index)")
      let events = Array(resolved.projection.events.dropFirst(prefix)).filter {
        fixture.full != true || $0.key == "language" || $0.key == "lazyMode"
      }
      XCTAssertEqual(events, fixture.events, "fixture \(index)")
      let next = try WebsiteConfigLazyModeLifecycle.prepare(resolved, pointsPerRem: 16, replayApplicationEvents: false)
      XCTAssertEqual(next.lazyMemory, resolved.lazyMemory, "Admitted state must be stable for ordinary next: \(index)")
      XCTAssertEqual(next.generators.lazyMode, resolved.generators.lazyMode)
    }
  }
}
