import XCTest
@testable import Typebar

final class WebsiteConfigRuntimeProjectionTests: XCTestCase {
  func testPinnedBulkMetadataSettersAndEventSequence() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard environment["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else {
      return XCTFail("Prepare pinned Zod with Scripts/prepare-website-config-schema-qa.sh")
    }
    struct Catalogs: Decodable {
      var languages: Set<String>, themes: Set<String>, layouts: Set<String>, fonts: Set<String>, funboxes: Set<String>
    }
    struct Gate: Decodable {
      var value: WebsiteConfigValue
      var current: [String: WebsiteConfigValue]
      var accepted: Bool
    }
    struct Fixture: Decodable {
      var normalized: [String: WebsiteConfigValue]
      var requested: [String: WebsiteConfigValue]
      var runtime: [String: WebsiteConfigValue]
      var rejectedKeys: [String]
      var events: [WebsiteConfigApplicationEvent]
      var flags: WebsiteConfigRuntimeContext
      var gate: Gate
    }
    struct Output: Decodable {
      var defaults: [String: WebsiteConfigValue]
      var catalogs: Catalogs
      var orderedKeys: [String]
      var fixtures: [Fixture]
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--runtime-projection"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    let schema = WebsiteConfigSchema(catalogs: .init(languages: output.catalogs.languages,
      themes: output.catalogs.themes, layouts: output.catalogs.layouts, fonts: output.catalogs.fonts,
      funboxes: output.catalogs.funboxes))
    XCTAssertEqual(output.fixtures.count, 671)
    for (index, fixture) in output.fixtures.enumerated() {
      var gateCalls = 0
      let projected = try WebsiteConfigRuntimeProjector.project(requested: fixture.normalized,
        defaults: output.defaults, orderedKeys: output.orderedKeys, schema: schema, context: fixture.flags,
        admitsFunbox: { value, current in
          gateCalls += 1
          XCTAssertEqual(value, fixture.gate.value, "gate value \(index)")
          assertFields(current, fixture.gate.current, "gate state \(index)")
          let accepted = WebsiteFunboxAdmission.accepts(value, current: current)
          XCTAssertEqual(accepted, fixture.gate.accepted, "native gate \(index)")
          return accepted
        })
      XCTAssertEqual(gateCalls, 1)
      assertFields(projected.runtime, fixture.runtime, "runtime \(index)")
      try WebsiteConfigNativeBehaviorTests.assertSourceRuntime(fixture.runtime)
      try WebsiteConfigNativeBehaviorTests.assertSourceRuntime(projected.runtime)
      let presentation = try WebsiteConfigNativePresentation(runtime: projected.runtime).applying(to: .init())
      assertFields(WebsiteConfigNativePresentationTests.nativeFields(presentation),
        WebsiteConfigNativePresentationTests.expectedFields(fixture.runtime), "native presentation \(index)")
      assertFields(projected.requested, fixture.requested, "request \(index)")
      XCTAssertEqual(projected.rejectedKeys, fixture.rejectedKeys, "rejections \(index)")
      XCTAssertEqual(projected.events.count, fixture.events.count, "event count \(index)")
      XCTAssertTrue(projected.events.filter { $0.newValue != nil }.allSatisfy { $0.nosave == true })
      XCTAssertNil(projected.events.first?.nosave)
      XCTAssertNil(projected.events.last?.nosave)
      if let mismatch = zip(projected.events, fixture.events).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
        XCTFail("fixture \(index) event \(mismatch.offset): \(mismatch.element)")
      }
      let productionDefault = try WebsiteConfigRuntimeProjector.project(requested: fixture.normalized,
        defaults: output.defaults, orderedKeys: output.orderedKeys, schema: schema, context: fixture.flags)
      assertFields(productionDefault.runtime, projected.runtime, "default provider runtime \(index)")
      assertFields(productionDefault.requested, projected.requested, "default provider request \(index)")
      XCTAssertEqual(productionDefault.rejectedKeys, projected.rejectedKeys)
      XCTAssertEqual(productionDefault.events, projected.events)
    }
    XCTAssertThrowsError(try WebsiteConfigRuntimeProjector.project(requested: output.defaults,
      defaults: output.defaults, orderedKeys: Array(repeating: output.orderedKeys[0], count: output.orderedKeys.count),
      schema: schema, context: .init(), admitsFunbox: { _, _ in XCTFail("Invalid order must not reach a gate"); return true }))
    var invalid = output.defaults
    invalid["words"] = .bool(true)
    XCTAssertThrowsError(try WebsiteConfigRuntimeProjector.project(requested: invalid,
      defaults: output.defaults, orderedKeys: output.orderedKeys, schema: schema, context: .init(),
      admitsFunbox: { _, _ in XCTFail("Invalid input must not reach a gate"); return true }))
  }

  private func assertFields(_ actual: [String: WebsiteConfigValue], _ expected: [String: WebsiteConfigValue],
    _ context: String, file: StaticString = #filePath, line: UInt = #line) {
    let fields = Set(actual.keys).union(expected.keys).filter { actual[$0] != expected[$0] }.sorted()
    XCTAssertTrue(fields.isEmpty, "\(context): differing fields \(fields)", file: file, line: line)
  }
}
