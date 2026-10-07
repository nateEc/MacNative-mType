import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class ResultHistoryFilterChoiceTests: XCTestCase {
  @MainActor func testWithoutACurrentApplicationEventTheDefaultBindingTogglesNormally() {
    XCTAssertNil(NSApp?.currentEvent)
    var selected: Set<TestMode> = [.time, .words]
    let choice = ResultHistoryFilterChoice.binding(for: .words,
      selection: Binding(get: { selected }, set: { selected = $0 }))
    choice.wrappedValue = false
    XCTAssertEqual(selected, [.time])
  }

  @MainActor func testShiftClickOnAnAlreadySelectedModeKeepsOnlyThatMode() {
    var selected = Set(TestMode.allCases)
    let selection = Binding(get: { selected }, set: { selected = $0 })
    let choice = ResultHistoryFilterChoice.binding(for: .words, selection: selection,
      modifierFlags: { .shift })
    XCTAssertTrue(choice.wrappedValue)
    choice.wrappedValue = false
    XCTAssertEqual(selected, [.words])
    XCTAssertTrue(choice.wrappedValue)
  }

  @MainActor func testShiftClickOnAnUnselectedModeReplacesTheGroup() {
    var selected: Set<TestMode> = [.time, .quote]
    let choice = ResultHistoryFilterChoice.binding(for: .words,
      selection: Binding(get: { selected }, set: { selected = $0 }), modifierFlags: { .shift })
    choice.wrappedValue = true
    XCTAssertEqual(selected, [.words])
  }

  @MainActor func testOrdinaryClickStillAddsAndRemovesIncludingAnEmptyGroup() {
    for flags: NSEvent.ModifierFlags in [[], .command, .option, .control] {
      var selected: Set<TestMode> = [.time]
      let selection = Binding(get: { selected }, set: { selected = $0 })
      let words = ResultHistoryFilterChoice.binding(for: .words, selection: selection,
        modifierFlags: { flags })
      words.wrappedValue = true
      XCTAssertEqual(selected, [.time, .words])
      words.wrappedValue = false
      let time = ResultHistoryFilterChoice.binding(for: .time, selection: selection,
        modifierFlags: { flags })
      time.wrappedValue = false
      XCTAssertTrue(selected.isEmpty)
    }
  }

  @MainActor func testModifiersAreReadAtActivationRatherThanBindingCreation() {
    var flags: NSEvent.ModifierFlags = []
    var selected = Set(Difficulty.allCases)
    let choice = ResultHistoryFilterChoice.binding(for: .expert,
      selection: Binding(get: { selected }, set: { selected = $0 }), modifierFlags: { flags })
    flags = [.shift, .option]
    choice.wrappedValue = false
    XCTAssertEqual(selected, [.expert])
    flags = []
    choice.wrappedValue = false
    XCTAssertTrue(selected.isEmpty)
  }

  @MainActor func testDropdownDerivedGroupsKeepOrdinarySemanticsWithShift() {
    var selected: Set<TypingLanguage> = [.english, .spanish]
    let choice = ResultHistoryFilterChoice.binding(for: .english,
      selection: Binding(get: { selected }, set: { selected = $0 }),
      allowsExclusiveSelection: false, modifierFlags: { .shift })
    choice.wrappedValue = false
    XCTAssertEqual(selected, [.spanish])
    choice.wrappedValue = true
    XCTAssertEqual(selected, [.english, .spanish])
  }

  @MainActor func testExclusiveChoiceFiltersResultsAndRoundTripsWithoutChangingOtherGroups() throws {
    var filter = ResultHistoryFilter(modes: Set(TestMode.allCases), languages: [.english],
      difficulties: Set(Difficulty.allCases))
    let choice = ResultHistoryFilterChoice.binding(for: TestMode.words,
      selection: Binding(get: { filter.modeSelections }, set: { filter.modes = $0 }),
      modifierFlags: { .shift })
    choice.wrappedValue = false
    let words = UUID(), time = UUID(), foreignLanguage = UUID()
    let rows = [ResultHistoryEntry(id: words, mode: .words, language: .english, tags: []),
      ResultHistoryEntry(id: time, mode: .time, language: .english, tags: []),
      ResultHistoryEntry(id: foreignLanguage, mode: .words, language: .spanish, tags: [])]
    XCTAssertEqual(filter.matchingIDs(entries: rows, personalBestIDs: []), [words])
    XCTAssertEqual(filter.languageSelections, [.english])
    XCTAssertEqual(filter.difficultySelections, Set(Difficulty.allCases))
    XCTAssertEqual(try JSONDecoder().decode(ResultHistoryFilter.self,
      from: JSONEncoder().encode(filter)), filter)
  }

  @MainActor func testEveryFiniteGroupAgainstPinnedActivationCallback() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-history-filter-choice.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
    struct Fixture: Decodable {
      let group: String; let values, selected: Set<String>; let value: String
      let shift: Bool; let expected: Set<String>
    }
    struct Document: Decodable {
      let referenceCommit: String; let groups: [String: Set<String>]; let fixtures: [Fixture]
    }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.fixtures.count, 1136)
    XCTAssertEqual(document.groups["mode"], Set(TestMode.allCases.map(\.rawValue)))
    XCTAssertEqual(document.groups["difficulty"], Set(Difficulty.allCases.map(\.rawValue)))
    XCTAssertEqual(document.groups["time"], Set(ResultHistoryTimeLimit.allCases.map(\.rawValue)))
    XCTAssertEqual(document.groups["words"], Set(ResultHistoryWordLimit.allCases.map(\.rawValue)))
    XCTAssertEqual(document.groups["quoteLength"], Set(QuoteLength.allCases.filter { $0 != .all }
      .map { $0 == .extended ? "thicc" : $0.rawValue }))
    for row in document.fixtures {
      var selected = row.selected
      let choice = ResultHistoryFilterChoice.binding(for: row.value,
        selection: Binding(get: { selected }, set: { selected = $0 }),
        modifierFlags: { row.shift ? .shift : [] })
      choice.wrappedValue = !choice.wrappedValue
      XCTAssertEqual(selected, row.expected, "\(row.group) / \(row.value) / Shift \(row.shift)")
      XCTAssertTrue(selected.isSubset(of: row.values))
    }
  }
}
