import XCTest
@testable import Typebar

@MainActor final class WebsiteRandomWordGeneratorTests: XCTestCase {
  func testPinnedPrimitiveOutputsAndEntropyConsumption() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable { let kind, word: String; let samples: [Double]; let draws: Int }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-random-words.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 100)
    for f in output.fixtures {
      let kind = try XCTUnwrap(WebsiteRandomWordGenerator.Kind(rawValue: f.kind))
      var draws = 0
      let word = WebsiteRandomWordGenerator.word(kind) {
        defer { draws += 1 }; return f.samples[draws % f.samples.count]
      }
      XCTAssertEqual(word, f.word, f.kind)
      XCTAssertEqual(draws, f.draws, f.kind)
    }
  }

  func testInvalidEntropyIsRefusedForEveryPrimitive() {
    for kind in WebsiteRandomWordGenerator.Kind.allCases {
      for unit in [-1, 1, Double.nan, Double.infinity] {
        XCTAssertNil(WebsiteRandomWordGenerator.word(kind, randomUnit: { unit }))
      }
    }
  }

  func testLegacyNativeBinaryKeepsItsIndependentIndexContract() {
    let configuration = TestConfiguration.words(3).with(modifiers: [.binaryStream])
    XCTAssertNil(WebsiteRandomWordGenerator.selected(for: configuration))
    XCTAssertEqual(TestSessionFactory.make(configuration: configuration).prompt, "00000000 00000001 00000010")
  }
}
