import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigFunboxActivationTests: XCTestCase {
  func testMemoryTapeRefusalDoesNotPreventItsLaterKeymapSetter() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":4,"funbox":["memory"],"tapeMode":"letter","showAllLines":false,"keymapMode":"next"}"#,
      pointsPerRem: 16, context: .init())
    let activated = try WebsiteConfigFunboxActivation.prepare(draft, pointsPerRem: 16, context: .init())
    XCTAssertEqual(activated.projection.runtime["showAllLines"], .bool(false))
    XCTAssertEqual(activated.projection.runtime["keymapMode"], .string("react"))
    XCTAssertEqual(Array(activated.projection.events.dropFirst(draft.projection.events.count)),
      [.init(key: "keymapMode", previousValue: .string("next"), newValue: .string("react"), nosave: true)])
  }
  func testPinnedActivationHandlersJoiningGuardAndRepeatedSetterOrder() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Notice: Decodable { let important: Bool }
    struct Fixture: Decodable {
      let current: [String: WebsiteConfigValue], after: [String: WebsiteConfigValue]
      let events: [WebsiteConfigApplicationEvent], repeatedEvents: [WebsiteConfigApplicationEvent]
      let notices: [Notice], repeatedNotices: [Notice]
    }
    struct MemoryFixture: Decodable {
      let current: [String: WebsiteConfigValue], activated: [String: WebsiteConfigValue], after: [String: WebsiteConfigValue]
      let selection: [String], events: [WebsiteConfigApplicationEvent]
    }
    struct Output: Decodable {
      let fixtures: [Fixture]; let rawEmptyLayoutFallback: String
      let memoryFixtures: [MemoryFixture]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-funbox-activation.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.rawEmptyLayoutFallback, "qwerty")
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    XCTAssertFalse(schema.accepts(.array([]), for: "customLayoutfluid"))
    let empty = try WebsiteConfigNativeProfile.prepareDraft(#"{"customLayoutfluid":[]}"#, pointsPerRem: 16, context: .init())
    XCTAssertEqual(empty.projection.runtime["customLayoutfluid"], try WebsiteConfigNativeProfile.defaultDocument().values["customLayoutfluid"])
    let fixtures = output.fixtures
    XCTAssertEqual(fixtures.count, 2304)
    for (index, fixture) in fixtures.enumerated() {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(WebsiteConfigJSONWriter.write(.object(fixture.current)),
        pointsPerRem: 16, context: .init())
      for (key, value) in fixture.current { XCTAssertEqual(draft.projection.runtime[key], value, "initial \(index) \(key)") }
      var cleared = 0
      let activated = try WebsiteConfigFunboxActivation.prepare(draft, pointsPerRem: 16, context: .init(),
        onJoiningScriptClear: { cleared += 1 })
      for (key, value) in fixture.after { XCTAssertEqual(activated.projection.runtime[key], value, "activation \(index) \(key)") }
      XCTAssertEqual(Array(activated.projection.events.dropFirst(draft.projection.events.count)), fixture.events, "setter order \(index)")
      XCTAssertEqual(cleared, fixture.notices.count)
      XCTAssertTrue(fixture.notices.allSatisfy { !$0.important })
      cleared = 0
      let repeated = try WebsiteConfigFunboxActivation.prepare(activated, pointsPerRem: 16, context: .init(),
        onJoiningScriptClear: { cleared += 1 })
      XCTAssertEqual(repeated.projection.runtime, activated.projection.runtime)
      XCTAssertEqual(Array(repeated.projection.events.dropFirst(activated.projection.events.count)), fixture.repeatedEvents, "repeat \(index)")
      XCTAssertEqual(cleared, fixture.repeatedNotices.count)
    }
    XCTAssertEqual(output.memoryFixtures.count, 225)
    for (index, fixture) in output.memoryFixtures.enumerated() {
      var draft = try WebsiteConfigNativeProfile.prepareDraft(WebsiteConfigJSONWriter.write(.object(fixture.current)),
        pointsPerRem: 16, context: .init())
      for _ in 0..<2 {
        draft = WebsiteConfigFunboxMemory.remembering(draft)
        draft = try WebsiteConfigFunboxActivation.prepare(draft, pointsPerRem: 16, context: .init())
      }
      for (key, value) in fixture.activated { XCTAssertEqual(draft.projection.runtime[key], value, "memory activation \(index) \(key)") }
      let selected = try WebsiteConfigFunboxMemory.selecting(.array(fixture.selection.map(WebsiteConfigValue.string)),
        from: draft, pointsPerRem: 16, context: .init(), testActive: false)
      XCTAssertEqual(selected.saved, fixture.events.contains { $0.key == "funbox" && $0.nosave == false })
      for (key, value) in fixture.after { XCTAssertEqual(selected.draft.projection.runtime[key], value, "memory restoration \(index) \(key)") }
      XCTAssertEqual(selected.draft.projection.events, fixture.events, "restoration setter order \(index)")
      XCTAssertTrue(selected.draft.funboxMemory.entries.isEmpty)
    }
  }
}
