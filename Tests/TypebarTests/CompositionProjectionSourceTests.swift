import Foundation
import XCTest
@testable import Typebar

@MainActor final class CompositionProjectionSourceTests: XCTestCase {
  private struct Cell: Decodable {
    let textUnits: [UInt16]
    let marked: Bool, correct: Bool, placeholder: Bool
  }
  private struct Fixture: Decodable {
    let mode: String
    let style: CompositionDisplayStyle
    let display: String, input: String, composition: String
    let tail: [Cell]
    let letterIndex: Int
  }
  private struct Evidence: Decodable {
    let pin: String
    let fixtures: [Fixture], unicodeFixtures: [Fixture]
  }
  private static var cachedEvidence: Evidence?

  private func evidence() throws -> Evidence {
    if let cached = Self.cachedEvidence { return cached }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", project.appendingPathComponent("Scripts/check-source-composition-projection.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let value = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(value.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(value.fixtures.count, 132); XCTAssertEqual(value.unicodeFixtures.count, 36)
    Self.cachedEvidence = value
    return value
  }

  func testMarkedTailAndCaretMatchCompletePinnedUpdateForAllBMPFixtures() throws {
    for fixture in try evidence().fixtures {
      let plan = PromptCompositionPlan(target: fixture.display, input: fixture.input,
        composition: fixture.composition, isZen: fixture.mode == "zen", style: fixture.style)
      let source = fixture.tail.filter { !$0.placeholder }
      let message = "\(fixture.mode)/\(fixture.style): target=\(String(reflecting: fixture.display)), input=\(String(reflecting: fixture.input)), marked=\(String(reflecting: fixture.composition))"
      XCTAssertEqual(plan.cells.count, source.count, message)
      for (cell, expected) in zip(plan.cells, source) {
        // Pending target controls retain their identities; the existing
        // renderer, not the marked-text planner, owns their native symbols.
        let text = cell.compositionIndex == nil ? cell.text.replacingOccurrences(of: "\t", with: "→")
          .replacingOccurrences(of: "\n", with: "↵") : cell.text
        XCTAssertEqual(Array(text.utf16), expected.textUnits, message)
        XCTAssertEqual(cell.compositionIndex != nil, expected.marked, message)
        XCTAssertEqual(cell.matchesTarget, expected.correct, message)
      }
      XCTAssertEqual(plan.hasEmptyPlaceholder, fixture.tail.contains(where: \.placeholder), message)
      XCTAssertEqual(plan.wordLetterIndex, fixture.letterIndex, message)
      XCTAssertEqual(plan.referenceLetterUnitIndex, fixture.letterIndex, message)
    }
  }

  func testPinnedUnicodeMixedUnitsAreExplicitAndNotCalledNativeGraphemeParity() throws {
    let fixtures = try evidence().unicodeFixtures
    let ordinary = try XCTUnwrap(fixtures.first {
      $0.mode == "words" && $0.style == .replace && $0.input == "a" && $0.composition == "😀"
    })
    XCTAssertEqual(ordinary.tail.prefix(2).map(\.textUnits), [[0xD83D], [0xDE00]])
    XCTAssertEqual(ordinary.letterIndex, 3)
    let native = PromptCompositionPlan(target: ordinary.display, input: ordinary.input,
      composition: ordinary.composition, isZen: false, style: .replace)
    XCTAssertEqual(native.cells.first?.text, "😀")
    XCTAssertEqual(native.wordLetterIndex, 2)
    XCTAssertEqual(native.referenceLetterUnitIndex, ordinary.letterIndex)
    XCTAssertEqual(native.replacedTargetRange, 1..<2)
    let zen = try XCTUnwrap(fixtures.first {
      $0.mode == "zen" && $0.style == .replace && $0.input == "a" && $0.composition == "😀"
    })
    XCTAssertEqual(zen.tail.first?.textUnits, [0xD83D, 0xDE00])
    XCTAssertEqual(zen.letterIndex, 3, "Source caret still counts UTF-16 while Zen cells iterate scalars")
    for fixture in fixtures where fixture.mode == "words" && fixture.style == .replace && fixture.input.isEmpty {
      XCTAssertTrue(fixture.tail.filter(\.marked).allSatisfy { !$0.correct })
      let plan = PromptCompositionPlan(target: fixture.display, input: fixture.input,
        composition: fixture.composition, isZen: false, style: .replace)
      XCTAssertEqual(plan.cells.first?.matchesTarget, false,
        "Canonical equivalence must not turn an originally wrong marked prefix into a correct one")
    }
  }
}
