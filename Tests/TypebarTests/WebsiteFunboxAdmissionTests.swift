import XCTest
@testable import Typebar

final class WebsiteFunboxAdmissionTests: XCTestCase {
  func testPinnedCombinationsAndConfigurationAdmission() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard environment["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Prepare pinned Zod QA dependency") }
    struct Compatibility: Decodable { var names: [String]; var accepted: Bool }
    struct Admission: Decodable { var names: [String]; var results: [Bool] }
    struct Combined: Decodable { var names: [String]; var profile: Int; var accepted: Bool }
    struct Output: Decodable {
      var names: Set<String>
      var compatibility: [Compatibility]
      var profiles: [[String: WebsiteConfigValue]]
      var admissions: [Admission]
      var combined: [Combined]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--funbox-admission"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.names, WebsiteFunboxAdmission.knownNames)
    XCTAssertEqual(output.compatibility.count, 21_958)
    XCTAssertEqual(output.profiles.count, 720)
    XCTAssertEqual(output.admissions.count, 48)
    XCTAssertEqual(output.combined.count, 11_520)
    var failures: [String] = []
    for fixture in output.compatibility where WebsiteFunboxAdmission.areCompatible(fixture.names) != fixture.accepted {
      failures.append("compatibility \(fixture.names)")
    }
    for fixture in output.admissions {
      XCTAssertEqual(fixture.results.count, output.profiles.count)
      for (profile, accepted) in zip(output.profiles.indices, fixture.results) {
        let value = WebsiteConfigValue.array(fixture.names.map(WebsiteConfigValue.string))
        if WebsiteFunboxAdmission.accepts(value, current: output.profiles[profile]) != accepted {
          failures.append("admission \(fixture.names) profile \(profile)")
        }
      }
    }
    for fixture in output.combined {
      if WebsiteFunboxAdmission.accepts(.array(fixture.names.map(WebsiteConfigValue.string)),
        current: output.profiles[fixture.profile]) != fixture.accepted {
        failures.append("combined \(fixture.names) profile \(fixture.profile)")
      }
    }
    XCTAssertTrue(failures.isEmpty, "\(failures.count) mismatches; first: \(Array(failures.prefix(12)))")
  }

  func testTypedBoundariesReplacementAndDormantLimits() {
    XCTAssertFalse(WebsiteFunboxAdmission.areCompatible(["mirror", "mirror"]))
    XCTAssertTrue(WebsiteFunboxAdmission.areCompatible(["rot13", "rot13"]))
    XCTAssertTrue(WebsiteFunboxAdmission.areCompatible(Array(repeating: "no_quit", count: 16)),
      "The separate schema, not combination compatibility, enforces the 15-item limit")
    XCTAssertTrue(WebsiteFunboxAdmission.areCompatible(["tts", "58008"]))
    XCTAssertFalse(WebsiteFunboxAdmission.areCompatible(["tts", "gibberish"]))
    XCTAssertFalse(WebsiteFunboxAdmission.areCompatible(["unknown"]))
    XCTAssertTrue(WebsiteFunboxAdmission.accepts(.array([]), current: [:]))
    XCTAssertFalse(WebsiteFunboxAdmission.accepts(.bool(true), current: [:]))
    XCTAssertFalse(WebsiteFunboxAdmission.accepts(.array([.bool(true)]), current: [:]))
    var current: [String: WebsiteConfigValue] = ["funbox": .array([.string("upside_down")]),
      "mode": .string("words"), "words": .number(50), "time": .number(30),
      "highlightMode": .string("letter"), "numbers": .bool(false), "punctuation": .bool(false)]
    XCTAssertTrue(WebsiteFunboxAdmission.accepts(.array([.string("mirror")]), current: current),
      "Combination checks apply to the replacement target, not old plus new CSS owners")
    current["funbox"] = .array([])
    current["time"] = .number(0)
    XCTAssertFalse(WebsiteFunboxAdmission.accepts(.array([.string("layoutfluid")]), current: current),
      "The inactive time limit is still inspected in a word test")
    current["time"] = .number(30)
    current["mode"] = .string("time")
    XCTAssertFalse(WebsiteFunboxAdmission.accepts(.array([.string("memory")]), current: current))
  }
}
