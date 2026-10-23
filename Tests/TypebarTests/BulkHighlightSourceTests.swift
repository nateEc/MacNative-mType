import XCTest
@testable import Typebar

@MainActor
final class BulkHighlightSourceTests: XCTestCase {
  func testPinnedBulkLifecycleDistinguishesRuntimeFromRequestedStore() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Row: Decodable {
      let highlight: String
      let runtimeFunbox: [String]
      let requestedFunbox: [String]
      let rejectedKeys: [String]
      let previousHighlight: String
    }
    struct Output: Decodable {
      let cases: [Row]
      let clearsPreviousFunbox: Bool
      let directConflictRejectedBeforeWrite: Bool
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-bulk-highlight.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.cases.map(\.highlight), ["letter", "off", "word", "next_word"])
    for row in output.cases {
      let compatible = row.highlight == "letter" || row.highlight == "off"
      XCTAssertEqual(row.runtimeFunbox, compatible ? ["read_ahead"] : [])
      XCTAssertEqual(row.requestedFunbox, ["read_ahead"])
      XCTAssertEqual(row.rejectedKeys, compatible ? [] : ["funbox"])
      XCTAssertEqual(row.previousHighlight, "letter")
    }
    XCTAssertTrue(output.clearsPreviousFunbox)
    XCTAssertTrue(output.directConflictRejectedBeforeWrite)
  }

  func testNativeSnapshotRestoreRemainsLosslessRatherThanPretendingToImportWebsiteConfig() throws {
    for source in [false, true] {
      let suite = "TypebarTests.NativeBulkHighlight.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      if source {
        XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot())))
      }
      let settings = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      var incoming = settings.snapshot
      incoming.promptHighlightMode = .word
      incoming.testModifiers = [.readAhead]
      XCTAssertTrue(settings.apply(incoming))
      XCTAssertEqual(settings.snapshot, incoming,
        "Native snapshots preserve requested preferences; website applyConfig has a distinct runtime projection")
      let reader = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      XCTAssertEqual(reader.snapshot, incoming)
      XCTAssertFalse(reader.promptHighlightWasInteractivelyAdmitted)
    }
  }
}
