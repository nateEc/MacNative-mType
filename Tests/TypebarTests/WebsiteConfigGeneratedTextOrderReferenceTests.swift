import XCTest
@testable import Typebar

final class WebsiteConfigGeneratedTextOrderReferenceTests: XCTestCase {
  func testActualSharedTransformerAgainstPinnedOrderedHandlersForRepresentableStrings() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable { let chain: [String], word: Int, index: Int, bound: Int, upper: Bool, output: [UInt16] }
    struct Output: Decodable { let words: [[UInt16]], fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-ordered-funbox-text.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 28_448)
    var checked = 0, nonrepresentable = 0, mismatches: [Int] = []
    for (index, item) in output.fixtures.enumerated() {
      let units = output.words[item.word]
      let input = String(decoding: units, as: UTF16.self)
      let expected = String(decoding: item.output, as: UTF16.self)
      // Swift String cannot own lone surrogates. The raw kernel's separate
      // oracle covers those; do not misreport repaired output as exact units.
      guard Array(input.utf16) == units, Array(expected.utf16) == item.output else {
        nonrepresentable += 1; continue
      }
      let order = try item.chain.map { name in
        try XCTUnwrap(FunboxCommandCatalog.target(for: "funbox.changeFunbox\(name)")?.modifier)
      }
      let result = TestModifierPolicy.transformedWord(input, modifiers: order,
        websiteOrder: order, wordIndex: item.index, wordBound: item.bound, nextRandomCaseBit: { item.upper })
      if Array(result.utf16) != item.output { mismatches.append(index) }
      checked += 1
    }
    XCTAssertGreaterThan(checked, 10_000); XCTAssertGreaterThan(nonrepresentable, 0)
    XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) shared-generator mismatches: \(mismatches.prefix(12))")
    print("Pinned shared-generator representable fixtures: \(checked); raw-only fixtures: \(nonrepresentable)")
  }
}
