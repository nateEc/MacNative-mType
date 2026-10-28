import XCTest
@testable import Typebar

final class WebsiteRandomThemeSequenceTests: XCTestCase {
  func testPinnedCompleteListShuffleAndDrawFunctionsIncludingAliasAndFaultStates() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Entry: Decodable { let name: String, dark: Bool }
    struct Action: Decodable { let kind: String, value: String?, names: [String]? }
    struct Draw: Decodable { let theme: String, customID: String? }
    struct Request: Decodable { let key: String, value: Bool, nosave: Bool }
    struct Frame: Decodable {
      let candidates: [String], cursor: Int, active: String?, alias: Bool, favorites: [String], randomCalls: Int
      let fault: String?, draw: Draw?, requests: [Request], notices: [String]
    }
    struct Fixture: Decodable { let favorites: [String], dark: Bool, customIDs: [String], actions: [Action], frames: [Frame] }
    struct Output: Decodable { let entries: [Entry], samples: [Double], fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-random-theme.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 53); XCTAssertEqual(output.fixtures.reduce(0) { $0 + $1.frames.count }, 498)
    var faults = 0, spins = 0
    for (fixtureID, f) in output.fixtures.enumerated() {
      var sequence = try WebsiteRandomThemeSequence(entries: output.entries.map { .init(name: $0.name, isDark: $0.dark) })
      var favorites = WebsiteRandomThemeSequence.Favorites(f.favorites), mode = RandomThemeMode.off
      var customIDs = f.customIDs, dark = f.dark, calls = 0, customEnabled = true
      func index(_ upper: Int) -> Int {
        let sample = output.samples[calls % output.samples.count]; calls += 1
        return Int(floor(sample * Double(upper + 1)))
      }
      for (offset, action) in f.actions.enumerated() {
        let expected = f.frames[offset]
        var draw: WebsiteRandomThemeSequence.Draw?, failure: WebsiteRandomThemeSequence.Failure?, cleared = false
        do {
          switch action.kind {
          case "mode", "silentMode":
            mode = try XCTUnwrap(RandomThemeMode(rawValue: XCTUnwrap(action.value)))
            if action.kind == "mode" { try sequence.rebuild(mode: mode, favorites: &favorites, customIDs: customIDs, chooseIndex: index) }
          case "favorites": favorites.replace(with: try XCTUnwrap(action.names))
          case "library": customIDs = try XCTUnwrap(action.names)
          case "system": dark.toggle()
          case "rebuild": try sequence.rebuild(mode: mode, favorites: &favorites, customIDs: customIDs, chooseIndex: index)
          case "draw":
            draw = try sequence.next(mode: mode, favorites: &favorites, customIDs: customIDs, systemIsDark: dark, chooseIndex: index)
            if draw != nil { customEnabled = false }
          case "clear": cleared = sequence.clearActive()
          default: XCTFail("Unknown source action")
          }
        } catch let error as WebsiteRandomThemeSequence.Failure { failure = error }
        if expected.fault == "nonterminating" {
          spins += 1; XCTAssertEqual(failure, .noMatchingScheme); break
        }
        if expected.fault == "TypeError" {
          faults += 1
          guard case .missingBuiltIn(let name) = failure else { return XCTFail("Expected source's missing built-in boundary") }
          XCTAssertEqual(name, expected.active)
        } else { XCTAssertNil(failure, "fixture \(fixtureID), action \(offset)") }
        XCTAssertEqual(sequence.candidates, expected.candidates); XCTAssertEqual(sequence.cursor, expected.cursor)
        XCTAssertEqual(sequence.active, expected.active); XCTAssertEqual(sequence.aliases(favorites), expected.alias)
        XCTAssertEqual(favorites.names, expected.favorites); XCTAssertEqual(calls, expected.randomCalls)
        if action.kind == "clear" {
          XCTAssertEqual(expected.draw?.theme, cleared ? (customEnabled ? "custom" : "serika_dark") : nil)
          XCTAssertNil(expected.draw?.customID); XCTAssertTrue(expected.requests.isEmpty)
        } else {
          XCTAssertEqual(draw?.theme, expected.draw?.theme); XCTAssertEqual(draw?.customSourceID, expected.draw?.customID)
          XCTAssertEqual(expected.requests.count, draw == nil ? 0 : 1)
        }
        XCTAssertTrue(expected.notices.isEmpty, "A single draw's wrap notice is unreachable after the immediate index reset")
        for request in expected.requests { XCTAssertEqual(request.key, "customTheme"); XCTAssertFalse(request.value); XCTAssertTrue(request.nosave) }
      }
    }
    XCTAssertEqual(faults, 57); XCTAssertEqual(spins, 1)
  }

  func testValueCopyKeepsUncommittedFavoriteShuffleOutOfTheOriginalSnapshot() throws {
    var original = try WebsiteRandomThemeSequence(entries: [.init(name: "serika", isDark: false), .init(name: "nord", isDark: true)])
    var saved = WebsiteRandomThemeSequence.Favorites(["serika", "nord"])
    try original.rebuild(mode: .favorites, favorites: &saved, customIDs: [], chooseIndex: { $0 })
    var prepared = original, prospective = saved
    try prepared.rebuild(mode: .favorites, favorites: &prospective, customIDs: [], chooseIndex: { _ in 0 })
    XCTAssertEqual(saved.names, ["serika", "nord"]); XCTAssertEqual(original.candidates, saved.names)
    XCTAssertEqual(prospective.names, ["nord", "serika"]); XCTAssertEqual(prepared.candidates, prospective.names)
    prospective.replace(with: [])
    XCTAssertFalse(prepared.aliases(prospective)); XCTAssertTrue(original.aliases(saved))
  }

  func testNoMatchingSystemSchemeIsBoundedAndInvalidCatalogOrRandomIndexIsRejected() throws {
    XCTAssertThrowsError(try WebsiteRandomThemeSequence(entries: [.init(name: "nord", isDark: true), .init(name: "nord", isDark: false)]))
    var sequence = try WebsiteRandomThemeSequence(entries: [.init(name: "nord", isDark: true)])
    var favorites = WebsiteRandomThemeSequence.Favorites([])
    XCTAssertThrowsError(try sequence.next(mode: .auto, favorites: &favorites, customIDs: [], systemIsDark: false)) {
      XCTAssertEqual($0 as? WebsiteRandomThemeSequence.Failure, .noMatchingScheme)
    }
    var invalid = try WebsiteRandomThemeSequence(entries: [.init(name: "nord", isDark: true), .init(name: "serika", isDark: false)])
    XCTAssertThrowsError(try invalid.rebuild(mode: .on, favorites: &favorites, customIDs: [], chooseIndex: { $0 + 1 })) {
      XCTAssertEqual($0 as? WebsiteRandomThemeSequence.Failure, .invalidShuffleIndex)
    }
  }
}
