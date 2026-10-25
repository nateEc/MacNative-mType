import XCTest
@testable import Typebar

@MainActor final class WebsiteThresholdCommandTests: XCTestCase {
  func testSpeedCommandConvertsEmptyInputToZeroWithoutClosingCustomMode() {
    XCTAssertEqual(WebsiteThresholdCommandInput.edits(for: .minimumWpmCustom, raw: "", unit: .wpm), [.speedValue(0)])
    XCTAssertEqual(WebsiteThresholdCommandInput.edits(for: .minimumAccuracyCustom, raw: "\u{feff} ", unit: .wpm), [.accuracyValue(0)])
  }
  func testBurstCommandUsesIntegerPrefixRatherThanWholeNumberParsing() {
    XCTAssertEqual(WebsiteThresholdCommandInput.edits(for: .minimumWordBurst(.fixed), raw: "1e3", unit: .wpm),
      [.burstMode(.fixed), .burstValue(1)])
    XCTAssertEqual(WebsiteThresholdCommandInput.edits(for: .minimumWordBurst(.flex), raw: "73.5tail", unit: .cpm),
      [.burstMode(.flex), .burstValue(14.6)])
  }
  private struct Scalar: Decodable {
    let value: WebsiteConfigValue
    init(from decoder: Decoder) throws {
      let box = try decoder.singleValueContainer()
      if let number = try? box.decode(Double.self) { value = .number(number) }
      else if let text = try? box.decode(String.self) { value = .string(text) }
      else {
        let tag = try box.decode([String:String].self)["$probeNumber"]
        switch tag {
        case "NaN": value = .number(.nan)
        case "Infinity": value = .number(.infinity)
        case "-Infinity": value = .number(-.infinity)
        default: throw DecodingError.dataCorruptedError(in: box, debugDescription: "Unknown source number")
        }
      }
    }
  }
  func testCommandPlansAndSetterEffectsMatchActualPinnedHandlersAcrossAllSpeedUnits() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Attempt: Decodable { let key: String, value: Scalar, accepted: Bool }
    struct Event: Decodable { let key: String, newValue: Scalar, nosave: Bool }
    struct Fixture: Decodable {
      let kind: String, raw: String, unit: TypingSpeedUnit, active: Bool, noQuit: Bool, canSubmit: Bool
      let attempts: [Attempt], runtime: [String:Scalar], events: [Event], saves: [String], notices: [Bool]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--threshold-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 3200)
    let defaults = try WebsiteConfigNativeProfile.defaultDocument().values
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    func same(_ actual: WebsiteConfigValue?, _ expected: WebsiteConfigValue, _ label: String) {
      if case .number(let a)? = actual, case .number(let b) = expected, a.isNaN && b.isNaN { return }
      XCTAssertEqual(actual, expected, label)
    }
    for (index, fixture) in fixtures.enumerated() {
      let target: PracticeThresholdCommandTarget
      switch fixture.kind {
      case "speed": target = .minimumWpmCustom
      case "accuracy": target = .minimumAccuracyCustom
      case "fixed": target = .minimumWordBurst(.fixed)
      default: target = .minimumWordBurst(.flex)
      }
      let edits = WebsiteThresholdCommandInput.edits(for: target, raw: fixture.raw, unit: fixture.unit)
      XCTAssertEqual(edits != nil, fixture.canSubmit, "admission \(index)")
      guard let edits else { continue }
      XCTAssertEqual(edits.count, fixture.attempts.count, "steps \(index)")
      var runtime = defaults
      runtime["funbox"] = .array(fixture.noQuit ? [.string("no_quit")] : [])
      for (key, value) in ["minWpm":WebsiteConfigValue.string("off"), "minWpmCustomSpeed":.number(73.5),
        "minAcc":.string("off"), "minAccCustom":.number(91.5), "minBurst":.string("off"), "minBurstCustomSpeed":.number(83.5)] { runtime[key] = value }
      var events: [WebsiteConfigApplicationEvent] = [], saves: [String] = [], refusals = 0
      for (position, edit) in edits.enumerated() {
        guard fixture.attempts.indices.contains(position) else { return XCTFail("Missing source attempt") }
        let expected = fixture.attempts[position]
        XCTAssertEqual(edit.key, expected.key); same(edit.value, expected.value.value, "input \(index)")
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: edit.key, value: edit.value,
          defaults: defaults, schema: schema, context: .init(), testActive: fixture.active)
        XCTAssertEqual(result.rejectedKeys.isEmpty, expected.accepted, "setter \(index)")
        if !result.rejectedKeys.isEmpty && fixture.active && fixture.noQuit { refusals += 1 }
        runtime = result.runtime; events += result.events; saves += result.events.filter { $0.nosave == false }.map(\.key)
      }
      XCTAssertEqual(events.count, fixture.events.count, "events \(index)")
      for (actual, expected) in zip(events, fixture.events) {
        XCTAssertEqual(actual.key, expected.key); same(actual.newValue, expected.newValue.value, "event \(index)")
        XCTAssertEqual(actual.nosave, expected.nosave)
      }
      XCTAssertEqual(saves, fixture.saves, "save intent \(index)")
      XCTAssertEqual(refusals, fixture.notices.count, "No Quit notices \(index)")
      for (key, expected) in fixture.runtime { same(runtime[key], expected.value, "runtime \(index) \(key)") }
    }
  }
}
