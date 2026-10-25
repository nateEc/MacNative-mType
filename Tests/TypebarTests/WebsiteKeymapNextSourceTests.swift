import XCTest
import AppKit
import SwiftUI
@testable import Typebar

@MainActor final class WebsiteKeymapNextSourceTests: XCTestCase {
  func testActualSourceInitialScalarAndPostInputUnitsRetainUndefinedHighlight() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_REFERENCE_ROOT"] ?? env["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else { throw XCTSkip("Requires pinned reference") }
    struct Snapshot: Decodable { let units: [UInt16]? }
    struct Fixture: Decodable { let target: String, inputs: [String], stop: String; let snapshots: [Snapshot] }
    struct Deletion: Decodable { let target: String, input: String; let wholeWord: Bool; let snapshots: [Snapshot] }
    struct Output: Decodable { let fixtures: [Fixture]; let deletions: [Deletion] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path, reference, "--keymap-next-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    let fixtures = output.fixtures
    XCTAssertEqual(fixtures.count, 24)
    for fixture in fixtures {
      var config = TestConfiguration.words(100)
      config.rules.stopOnErrorMode = try XCTUnwrap(StopOnErrorMode(rawValue: fixture.stop))
      config.rules.blindMode = true
      var session = TypingSession(configuration: config, prompt: fixture.target + " tail")
      XCTAssertEqual(session.websiteKeymapHighlightUnits, fixture.snapshots[0].units, "Initial \(fixture.target.debugDescription)")
      for (index, input) in fixture.inputs.enumerated() {
        session.insertBatch(input, at: Date(timeIntervalSince1970: 4000))
        XCTAssertEqual(session.websiteKeymapHighlightUnits, fixture.snapshots[index + 1].units,
          "\(fixture.target.debugDescription), \(fixture.stop), input[\(index)]=\(input.debugDescription)")
      }
    }
    print("Pinned next-key producer sequences: \(fixtures.count)")
    XCTAssertEqual(output.deletions.count, 4)
    for fixture in output.deletions {
      var config = TestConfiguration.words(100)
      config.rules.blindMode = true; config.rules.freedomMode = true
      var session = TypingSession(configuration: config, prompt: fixture.target + " tail")
      session.insertBatch(fixture.input, at: Date(timeIntervalSince1970: 4000))
      for snapshot in fixture.snapshots {
        if fixture.wholeWord { session.deleteWordBackward() } else { session.deleteBackward() }
        XCTAssertEqual(session.websiteKeymapHighlightUnits, snapshot.units, "Delete \(fixture.target.debugDescription), wholeWord=\(fixture.wholeWord)")
      }
    }
  }

  func testCompositionRefreshUsesAcceptedUnitsWithoutScoringOrRecreatingAttempt() {
    var session = TypingSession(configuration: .words(100), prompt: "🙂x tail")
    let attempt = session.automaticInputAttemptID
    XCTAssertEqual(session.websiteKeymapHighlightUnits, [55357, 56898])
    session.beginComposition(at: Date(timeIntervalSince1970: 4000))
    session.refreshLiveAccuracyAfterComposition(hadMarkedText: false, hasMarkedText: true)
    XCTAssertEqual(session.websiteKeymapHighlightUnits, [55357])
    XCTAssertEqual(session.typed, ""); XCTAssertTrue(session.keymapInputEvents.isEmpty)
    XCTAssertEqual(session.errors, 0); XCTAssertEqual(session.automaticInputAttemptID, attempt)
  }

  func testHiddenGuideUsesRawProducerUnitsAndDoesNotDecodeSurrogatesOrFallBackFromExplicitAbsence() async throws {
    let rows: [[KeyboardGuideKey]] = [[], ["e", "e\u{301}", "\u{301}", "�"].enumerated().map {
      KeyboardGuideKey("owned-\($0.offset)", label: $0.element, width: 40).withWebsiteLegends([$0.element, $0.element, "", ""])
    }, [], []]
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 700, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: AnyView(Color.white))
    window.contentView = host; defer { window.contentView = nil; window.close() }
    var starts: [[Int]] = []
    for units: [UInt16]? in [[101], [769], [55357], nil] {
      host.rootView = AnyView(KeyboardGuide(nextCharacter: "e\u{301}", mode: .next, feedback: nil,
        accent: .blue, panel: .white, layout: .ansiQwerty, overrideRows: rows, overrideThumbKeys: [],
        websiteHighlight: .init(units: units), mirrored: false, scale: 2, legendStyle: .dynamic,
        keysMode: .minimal, style: .staggered, modifierFlags: [], capsLockEnabled: false)
        .frame(width: 700, height: 200).background(Color.white).environment(\.colorScheme, .light))
      host.frame = .init(x: 0, y: 0, width: 700, height: 200)
      try await Task.sleep(for: .milliseconds(60)); host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      var columns = Array(repeating: 0, count: bitmap.pixelsWide)
      for x in columns.indices { for y in 0..<bitmap.pixelsHigh {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.blueComponent > 0.5, c.blueComponent - c.redComponent > 0.18, c.blueComponent - c.greenComponent > 0.08 { columns[x] += 1 }
      } }
      starts.append(columns.indices.filter { columns[$0] > 5 && ($0 == 0 || columns[$0 - 1] <= 5) })
      XCTAssertFalse(window.isVisible)
    }
    XCTAssertEqual(starts.map(\.count), [1, 1, 0, 0])
    if let first = starts[0].first, let second = starts[1].first { XCTAssertEqual(second - first, 176, accuracy: 5) }
    print("Hidden raw next-key positions: \(starts)")
  }
}
