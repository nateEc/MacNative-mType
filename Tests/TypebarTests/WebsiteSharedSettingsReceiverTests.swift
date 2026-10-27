import XCTest
@testable import Typebar

@MainActor final class WebsiteSharedSettingsReceiverTests: XCTestCase {
  private struct Output: Decodable { let fixtures: [Fixture] }
  private struct Fixture: Decodable {
    struct Checkpoint: Decodable { let key: String, json: String }
    let label: String, json: String, active: Bool, initial: String, initialStore: String, initialCustom: String
    let runtime: String, store: String, custom: String, events: String, saves: [String], busy: Bool, activeAfter: Bool
    let configCheckpoints: [Checkpoint], customWrites: [String], requests: [String], starts: Int, inits: Int
    let selectedQuote: Double?, parseRejected: Bool, threw: Bool
    let selectedQuoteText: String?, configWrites: [String], initialSaved: String, saved: String
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
    }
  }
  private func oracle() throws -> Output {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned source, real Solid, Zod and LZ preparation")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--shared-test-settings"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data)
  }
}
