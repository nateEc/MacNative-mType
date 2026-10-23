import Foundation
import XCTest
@testable import Typebar

final class WebsiteConfigBackgroundFilterTests: XCTestCase {
  private typealias Filter = WebsiteConfigNativePagePreferences.BackgroundFilter

  func testWholeDeclarationRejectsInvalidComponentWithoutPartiallyUpdatingPreviousFilter() {
    var state = WebsiteConfigBackgroundFilter()
    XCTAssertEqual(state.apply(.init(blurRem: 0.2, brightness: 2.5, saturation: 4, opacity: 0.4)), .replaced)
    let previous = state.stages
    for position in 0..<4 {
      for invalid in [-1.0, -.infinity, .infinity, .nan] {
        var values = [0.0, 0.5, 0.0, 0.8]
        values[position] = invalid
        XCTAssertEqual(state.apply(Filter(blurRem: values[0], brightness: values[1],
          saturation: values[2], opacity: values[3])), .ignoredInvalidDeclaration)
        XCTAssertEqual(state.stages, previous, "Do not retain only the valid new components")
      }
    }
  }

  func testOrderedStagesKeepSourceUnitsAndUnboundedBrightnessAndSaturation() {
    var state = WebsiteConfigBackgroundFilter()
    XCTAssertEqual(state.apply(.init(blurRem: 60, brightness: 5, saturation: 7, opacity: 3)), .replaced)
    XCTAssertEqual(state.stages, [.blur(rem: 60), .brightness(multiplier: 5),
      .saturate(multiplier: 7), .opacity(multiplier: 1)])
    XCTAssertEqual(state.apply(.init(blurRem: 0, brightness: 0, saturation: 0, opacity: 0)), .replaced)
    XCTAssertEqual(state.stages, [.brightness(multiplier: 0), .saturate(multiplier: 0), .opacity(multiplier: 0)])
  }

  func testDefaultEmptyDeclarationClearsPreviousStagesAndSignedZeroBlurIsOmitted() {
    var state = WebsiteConfigBackgroundFilter()
    _ = state.apply(.init(blurRem: 1, brightness: 2, saturation: 3, opacity: 0.5))
    XCTAssertEqual(state.apply(.init(blurRem: -0.0, brightness: 1, saturation: 1, opacity: 1)), .replaced)
    XCTAssertEqual(state.stages, [])
    _ = state.apply(.init(blurRem: 0, brightness: -0.0, saturation: -0.0, opacity: -0.0))
    XCTAssertEqual(state.stages.count, 3, "Signed zero is valid, not a negative parameter")
  }

  func testReplacementImageStartsWithNoPreviousDeclaration() {
    var oldImage = WebsiteConfigBackgroundFilter()
    _ = oldImage.apply(.init(blurRem: 1, brightness: 2, saturation: 1, opacity: 1))
    var replacement = WebsiteConfigBackgroundFilter()
    XCTAssertEqual(replacement.apply(.init(blurRem: -1, brightness: 3, saturation: 1, opacity: 1)),
      .ignoredInvalidDeclaration)
    XCTAssertEqual(replacement.stages, [])
    XCTAssertFalse(oldImage.stages.isEmpty, "History belongs to an image, not to global configuration")
  }

  func testPinnedSetterOutputsAgainstNativeOrderedDeclarations() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"]
    else { throw XCTSkip("Requires pinned reference checkout") }
    struct Fixture: Decodable { let values: [String], css: String }
    struct Result: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-background-filter.mjs").path, reference]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let result = try JSONDecoder().decode(Result.self, from: data)
    XCTAssertEqual(result.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(result.fixtures.count, 33)
    func number(_ string: String) throws -> Double {
      switch string {
      case "Infinity": return .infinity
      case "-Infinity": return -.infinity
      case "NaN": return .nan
      default: return try XCTUnwrap(Double(string))
      }
    }
    var state = WebsiteConfigBackgroundFilter()
    for fixture in result.fixtures {
      let values = try fixture.values.map(number)
      let previous = state.stages
      let update = state.apply(Filter(blurRem: values[0], brightness: values[1],
        saturation: values[2], opacity: values[3]))
      // Interpret the emitted source declaration using the CSS function domains,
      // independently of native omission/order decisions. Not a browser oracle.
      var expected: [WebsiteConfigBackgroundFilter.Stage] = []
      var valid = true
      for term in fixture.css.split(separator: " ") {
        let pieces = term.split(separator: "(", maxSplits: 1)
        XCTAssertEqual(pieces.count, 2)
        let name = String(pieces[0])
        var value = String(pieces[1].dropLast())
        if name == "blur" { XCTAssertTrue(value.hasSuffix("rem")); value.removeLast(3) }
        let amount = try number(value)
        if !amount.isFinite || amount < 0 { valid = false; continue }
        switch name {
        case "blur": expected.append(.blur(rem: amount))
        case "brightness": expected.append(.brightness(multiplier: amount))
        case "saturate": expected.append(.saturate(multiplier: amount))
        case "opacity": expected.append(.opacity(multiplier: min(amount, 1)))
        default: XCTFail("Unexpected source filter: \(name)")
        }
      }
      XCTAssertEqual(update, valid ? .replaced : .ignoredInvalidDeclaration, fixture.css)
      XCTAssertEqual(state.stages, valid ? expected : previous, fixture.css)
    }
  }
}
