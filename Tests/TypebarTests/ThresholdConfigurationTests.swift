import XCTest
@testable import Typebar

final class ThresholdConfigurationTests: XCTestCase {
  func testOffChangesOnlyModeAndZeroDoesNotBecomeADifferentSpeed() throws {
    var value = PracticeThresholdConfiguration()
    try value.apply(.minimumWpm(mode: .custom, customValue: 45.5))
    try value.apply(.minimumWpm(mode: .off, customValue: nil))
    XCTAssertEqual(value.minimumWpmCustomValue, 45.5)
    try value.apply(.minimumAccuracy(mode: .custom, customValue: 92.25))
    try value.apply(.minimumAccuracy(mode: .off, customValue: nil))
    XCTAssertEqual(value.minimumAccuracyCustomValue, 92.25)
    try value.apply(.minimumWordBurst(mode: .flex, customValue: 72))
    try value.apply(.minimumWordBurst(mode: .off, customValue: nil))
    XCTAssertEqual(value.minimumWordBurstCustomValue, 72)
    try value.apply(.minimumWordBurst(mode: .fixed, customValue: 0))
    XCTAssertEqual(value.minimumWordBurstMode, .fixed)
    XCTAssertEqual(value.minimumWordBurstCustomValue, 0)
  }

  func testValueOnlyUpdatesDoNotEnableDisabledRulesAndRoundTripAllSixFields() throws {
    var value = PracticeThresholdConfiguration()
    try value.apply(.minimumWpm(mode: nil, customValue: 31))
    try value.apply(.minimumAccuracy(mode: nil, customValue: 83))
    try value.apply(.minimumWordBurst(mode: nil, customValue: 60.2))
    XCTAssertEqual(value.minimumWpmMode, .off)
    XCTAssertEqual(value.minimumAccuracyMode, .off)
    XCTAssertEqual(value.minimumWordBurstMode, .off)
    XCTAssertEqual(value.minimumWpmCustomValue, 31)
    XCTAssertEqual(value.minimumAccuracyCustomValue, 83)
    XCTAssertEqual(value.minimumWordBurstCustomValue, 60.2)
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(PracticeThresholdConfiguration.self, from: data), value)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(object.count, 6)
  }

  func testInvalidChangesAreAtomicAndInvalidEncodedValuesAreNotNormalized() throws {
    for change: PracticeThresholdConfiguration.Change in [
      .minimumWpm(mode: .custom, customValue: -1),
      .minimumAccuracy(mode: .custom, customValue: 101),
      .minimumWordBurst(mode: .fixed, customValue: .infinity),
      .minimumWordBurst(mode: .flex, customValue: .nan),
    ] {
      var value = PracticeThresholdConfiguration()
      let before = value
      XCTAssertThrowsError(try value.apply(change))
      XCTAssertEqual(value, before)
    }
    let data = try JSONEncoder().encode(PracticeThresholdConfiguration())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["minimumAccuracyCustomValue"] = 101
    XCTAssertThrowsError(try JSONDecoder().decode(PracticeThresholdConfiguration.self,
      from: JSONSerialization.data(withJSONObject: object)))
  }

  func testDefaultsAndCompleteBurstCommandsMatchThePinnedSource() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-threshold-configuration.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    struct Fixture: Decodable {
      let choice: String
      let input: String?
      let unit: String
      let state: PracticeThresholdConfiguration
    }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 7)
    var value = PracticeThresholdConfiguration()
    for item in fixtures {
      if item.choice != "initial" {
        let mode = try XCTUnwrap(MinimumWordBurstMode(rawValue: item.choice))
        let number: Double?
        if let input = item.input {
          number = try XCTUnwrap(PracticeThresholdInput.value(from: input, kind: .wordBurst,
            unit: item.unit == "cpm" ? .cpm : .wpm))
        } else { number = nil }
        try value.apply(.minimumWordBurst(mode: mode, customValue: number))
      }
      XCTAssertEqual(value, item.state, item.choice)
    }
  }

  func testCustomZeroModesAndMissingOrUnknownFieldsAreNotCollapsedIntoDefaults() throws {
    var value = PracticeThresholdConfiguration()
    try value.apply(.minimumWpm(mode: .custom, customValue: 0))
    try value.apply(.minimumAccuracy(mode: .custom, customValue: 0))
    try value.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    let data = try JSONEncoder().encode(value)
    let restored = try JSONDecoder().decode(PracticeThresholdConfiguration.self, from: data)
    XCTAssertEqual(restored.minimumWpmMode, .custom)
    XCTAssertEqual(restored.minimumAccuracyMode, .custom)
    XCTAssertEqual(restored.minimumWordBurstMode, .flex)
    XCTAssertEqual(restored, value)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "minimumWpmCustomValue")
    XCTAssertThrowsError(try JSONDecoder().decode(PracticeThresholdConfiguration.self,
      from: JSONSerialization.data(withJSONObject: object)))
    object["minimumWpmCustomValue"] = 0
    object["minimumAccuracyMode"] = "unknown"
    XCTAssertThrowsError(try JSONDecoder().decode(PracticeThresholdConfiguration.self,
      from: JSONSerialization.data(withJSONObject: object)))
  }

  func testFiniteSpeedDomainAndAccuracyEndpointsAreNotClampedToLegacyEditorLimits() throws {
    for speed in [0.25, 301.25, Double.greatestFiniteMagnitude] {
      var value = PracticeThresholdConfiguration()
      try value.apply(.minimumWpm(mode: .custom, customValue: speed))
      try value.apply(.minimumWordBurst(mode: .flex, customValue: speed))
      XCTAssertEqual(value.minimumWpmCustomValue, speed)
      XCTAssertEqual(value.minimumWordBurstCustomValue, speed)
      XCTAssertEqual(try JSONDecoder().decode(PracticeThresholdConfiguration.self,
        from: JSONEncoder().encode(value)), value)
    }
    for accuracy in [0.0, 100] {
      var value = PracticeThresholdConfiguration()
      try value.apply(.minimumAccuracy(mode: .custom, customValue: accuracy))
      XCTAssertEqual(value.minimumAccuracyCustomValue, accuracy)
      XCTAssertEqual(value.minimumAccuracyMode, .custom)
    }
  }
}
