import Foundation
import SwiftUI
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
    let cells: [Cell]
    let letterIndex: Int
  }
  private struct Evidence: Decodable {
    let pin: String
    let fixtures: [Fixture], unicodeFixtures: [Fixture]
    let returnFixtures: [Fixture]
    let fieldFixtures: [FieldFixture]
  }
  private struct FieldFixture: Decodable {
    let words: [String]
    let hidden: Bool, zen: Bool, strict: Bool, stop: Bool
    let accepted: String
    let index: Int, letterIndex: Int
    let targetUnits: [UInt16], inputUnits: [UInt16]
    let marked: [Cell]
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
    XCTAssertEqual(value.fieldFixtures.count, 15)
    XCTAssertEqual(value.returnFixtures.count, 24)
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

  func testActualReturnFieldCellsMatchPinnedUpdateWithoutDuplicatingWrongInput() throws {
    let fixtures = try evidence().returnFixtures.filter { $0.mode == "words" && $0.style == .replace }
    XCTAssertEqual(fixtures.count, 4)
    for fixture in fixtures {
      var session = TypingSession(configuration: .words(2), prompt: fixture.display + "bb")
      session.insertBatch(fixture.input, at: Date(timeIntervalSinceReferenceDate: 915_100_000))
      let before = session.typed
      let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session,
        composition: fixture.composition, style: .replace))
      let rendering = presentation.render { index, glyph, cell in
        AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off,
          isZen: false, compositionReplacement: cell?.text,
          isEmptyWordPlaceholder: index == presentation.emptyPlaceholderIndex).text)
      }
      let field = try XCTUnwrap(rendering.compositionTextMap?.fieldRuns.first { $0.fieldID == 0 })
      let source = fixture.cells.filter { !$0.placeholder }
      let message = "input=\(fixture.input), marked=\(fixture.composition)"
      XCTAssertEqual(field.cells.count, source.count, message)
      let markedIDs = Set(presentation.projection.markedCells.map(\.id))
      for (cell, expected) in zip(field.cells, source) {
        let main = ASLPromptGlyphContent(glyph: cell.glyph, text: cell.text).main
        XCTAssertEqual(Array(String(main.characters).utf16), expected.textUnits, message)
        XCTAssertEqual(markedIDs.contains(cell.id), expected.marked, message)
        XCTAssertEqual(cell.glyph.state == .correct, expected.correct, message)
      }
      XCTAssertEqual(session.typed, before, "Projection must not mutate accepted input")
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

  func testActualSessionFieldsMatchCompletePinnedWordsAndEventGetters() throws {
    for fixture in try evidence().fieldFixtures {
      let configuration = TestConfiguration(mode: fixture.zen ? .zen : .custom,
        duration: nil, wordLimit: nil, difficulty: .normal,
        rules: .init(strictSpace: fixture.strict, stopOnErrorMode: fixture.stop ? .letter : .off),
        modifiers: fixture.hidden ? [.noSpaces] : [])
      let prompt = fixture.words.joined()
      let batch = TransformedPromptBatch(text: prompt, noSpaceTargetWords: fixture.hidden ? fixture.words : [])
      var session = TypingSession(configuration: configuration, prompt: prompt,
        noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: batch.noSpaceWordLengths),
        noSpaceTargetWords: batch.noSpaceTargetWords)
      session.insertBatch(fixture.accepted, at: Date(timeIntervalSinceReferenceDate: 915_100_000))
      let field = try XCTUnwrap(session.promptCompositionField, fixture.words.description)
      XCTAssertEqual(field.index, fixture.index, fixture.words.description)
      XCTAssertEqual(field.targetUTF16, fixture.targetUnits, fixture.words.description)
      XCTAssertEqual(field.inputUTF16, fixture.inputUnits, fixture.words.description)
      let plan = PromptCompositionPlan(field: field, composition: "XYZ", style: .replace)
      XCTAssertEqual(plan.referenceLetterUnitIndex, fixture.letterIndex)
      XCTAssertEqual(field.boundary, fixture.zen ? .zen : fixture.hidden ? .hidden : .separated)
    }
  }

  func testGlobalMarkedOwnershipAndReferenceCaretMatchCompletePinnedFieldUpdates() throws {
    for fixture in try evidence().fieldFixtures {
      let configuration = TestConfiguration(mode: fixture.zen ? .zen : .custom,
        duration: nil, wordLimit: nil, difficulty: .normal,
        rules: .init(strictSpace: fixture.strict, stopOnErrorMode: fixture.stop ? .letter : .off),
        modifiers: fixture.hidden ? [.noSpaces] : [])
      let prompt = fixture.words.joined()
      let batch = TransformedPromptBatch(text: prompt, noSpaceTargetWords: fixture.hidden ? fixture.words : [])
      var session = TypingSession(configuration: configuration, prompt: prompt,
        noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: batch.noSpaceWordLengths),
        noSpaceTargetWords: batch.noSpaceTargetWords)
      session.insertBatch(fixture.accepted, at: Date(timeIntervalSinceReferenceDate: 915_100_000))
      let acceptedBeforeProjection = session.typed
      let fieldBeforeProjection = session.promptCompositionField?.inputUTF16
      let result = try XCTUnwrap(session.promptCompositionProjection(composition: "XYZ", style: .replace))
      XCTAssertEqual(result.markedCells.map(\.displayUTF16), fixture.marked.map(\.textUnits))
      XCTAssertTrue(result.markedCells.allSatisfy { $0.sourceFieldIndex == fixture.index })
      XCTAssertEqual(result.referenceLetterUnitIndex, fixture.letterIndex)
      XCTAssertEqual(Set(result.cells.map(\.id)).count, result.cells.count)
      // Source ordinary marked slots count UTF-16; native consumes field
      // graphemes. Compare correctness only where those units coincide.
      if fixture.targetUnits.allSatisfy({ $0 < 128 }) {
        XCTAssertEqual(result.markedCells.map(\.matchesTarget), fixture.marked.map(\.correct))
      }
      XCTAssertEqual(session.typed, acceptedBeforeProjection)
      XCTAssertEqual(session.promptCompositionField?.inputUTF16, fieldBeforeProjection)
    }
  }
}
