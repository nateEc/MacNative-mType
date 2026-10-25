import XCTest
@testable import Typebar

final class WebsiteConfigNativeQuoteSelectionTests: XCTestCase {
  static let quotes: [OfflineQuote] = [
    ("101", QuoteLength.short), ("102", .short), ("103", .medium), ("104", .long), ("105", .extended),
  ].map { OfflineQuote(id: $0.0, title: "Owned QA", text: "Owned QA sample \($0.0)", language: .english, length: $0.1) }

  static func selection(_ groups: [Int]) throws -> WebsiteConfigNativeQuoteSelection {
    try .init(runtime: ["quoteLength": .array(groups.map { .number(Double($0)) })])
  }

  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue], expected: [String: WebsiteConfigValue]? = nil) throws {
    let draft = try WebsiteConfigNativeQuoteSelection(runtime: runtime)
    XCTAssertEqual(draft.websiteValue, (expected ?? runtime)["quoteLength"])
  }

  private func quoteID(_ draw: WebsiteQuoteSampler.Draw) throws -> String {
    let id: String?
    if case .quote(let quote) = draw { id = quote.id } else { id = nil }
    return try XCTUnwrap(id, "Expected a quote, got \(draw)")
  }

  private func counts(_ ids: [String]) -> [String: Int] {
    ids.reduce(into: [:]) { $0[$1, default: 0] += 1 }
  }

  func testDuplicateGroupsAreWeightedWithoutReplacementAndCyclesMayRepeat() throws {
    var sampler = try WebsiteQuoteSampler(selection: Self.selection([0, 0, 1]), quotes: Self.quotes)
    XCTAssertEqual(sampler.cycleSize, 5)
    XCTAssertEqual(sampler.storageEntryCount, 3)
    var bounds: [Int] = []
    var ids: [String] = []
    for _ in 0..<10 {
      ids.append(try quoteID(sampler.next(randomIndex: { bounds.append($0); return 0 })))
    }
    XCTAssertEqual(bounds, [5, 4, 3, 2, 1, 5, 4, 3, 2, 1])
    XCTAssertEqual(Array(ids.prefix(2)), ["101", "101"])
    XCTAssertEqual(counts(Array(ids.prefix(5))), ["101": 2, "102": 2, "103": 1])
    XCTAssertEqual(counts(Array(ids.suffix(5))), ["101": 2, "102": 2, "103": 1])
    var firstDraws: [String] = []
    for ticket in 0..<5 {
      var fresh = try WebsiteQuoteSampler(selection: Self.selection([0, 0, 1]), quotes: Self.quotes)
      firstDraws.append(try quoteID(fresh.next(randomIndex: { _ in ticket })))
    }
    XCTAssertEqual(counts(firstDraws), ["101": 2, "102": 2, "103": 1])
    var boundary = try WebsiteQuoteSampler(selection: Self.selection([0]), quotes: Self.quotes)
    XCTAssertEqual(try quoteID(boundary.next(randomIndex: { _ in 0 })), "101")
    XCTAssertEqual(try quoteID(boundary.next(randomIndex: { _ in 0 })), "102")
    XCTAssertEqual(try quoteID(boundary.next(randomIndex: { $0 - 1 })), "102")
  }

  func testFailuresReportExactRecoveryWithoutNormalizingSelectionOrStaleFavorites() throws {
    for groups in [[], [-2, -2], [-2, -2, -2]] {
      var sampler = try WebsiteQuoteSampler(selection: Self.selection(groups), quotes: Self.quotes)
      XCTAssertEqual(try sampler.next(), .unavailable(.noSelectedLengthQuotes, recovery: .allLengths))
      XCTAssertEqual(sampler.selection.groups, groups)
    }
    var selected = try WebsiteQuoteSampler(selection: Self.selection([-2]), quotes: Self.quotes)
    XCTAssertEqual(try quoteID(selected.next(selectedQuoteID: "104")), "104")
    XCTAssertEqual(try selected.next(selectedQuoteID: "999"), .unavailable(.selectedQuoteUnavailable, recovery: .allLengths))
    var favorites = try WebsiteQuoteSampler(selection: Self.selection([-2, -3, 0]), quotes: Self.quotes)
    XCTAssertEqual(try favorites.next(), .unavailable(.favoriteQuoteUnavailable, recovery: .allLengths))
    XCTAssertEqual(try favorites.next(favoriteIDs: ["999", "101"], randomIndex: { _ in 0 }),
      .unavailable(.favoriteQuoteUnavailable, recovery: .allLengths))
    for _ in 0..<3 {
      XCTAssertEqual(try quoteID(favorites.next(favoriteIDs: ["101", "102"], randomIndex: { _ in 0 })), "101")
    }
    var empty = try WebsiteQuoteSampler(selection: Self.selection([-2]), quotes: [])
    XCTAssertEqual(try empty.next(selectedQuoteID: "101"), .unavailable(.noLanguageQuotes, recovery: .wordsMode))
  }

  func testInvalidRandomnessDoesNotConsumeOrResetCycleAndCopiesAreIndependent() throws {
    var sampler = try WebsiteQuoteSampler(selection: Self.selection([0]), quotes: Self.quotes)
    XCTAssertEqual(try quoteID(sampler.next(randomIndex: { _ in 0 })), "101")
    var copy = sampler
    XCTAssertThrowsError(try sampler.next(randomIndex: { $0 })) {
      XCTAssertEqual($0 as? WebsiteConfigNativeQuoteSelectionError, .invalidRandomIndex)
    }
    XCTAssertEqual(try sampler.next(randomIndex: { _ in 0 }), try copy.next(randomIndex: { _ in 0 }))
    XCTAssertThrowsError(try sampler.next(randomIndex: { _ in -1 }))
    XCTAssertEqual(try sampler.next(randomIndex: { _ in 0 }), try copy.next(randomIndex: { _ in 0 }))
    sampler.resetCycle()
    XCTAssertEqual(try quoteID(sampler.next(randomIndex: { _ in 0 })), "101")
    XCTAssertEqual(try quoteID(copy.next(randomIndex: { _ in 0 })), "102")
  }

  func testLargeDuplicateSelectionStoresCountsAndWebsiteJSONKeepsIntent() throws {
    let draft = try Self.selection(Array(repeating: 0, count: 100_000))
    var sampler = try WebsiteQuoteSampler(selection: draft, quotes: Self.quotes)
    XCTAssertEqual(sampler.cycleSize, 200_000)
    XCTAssertEqual(sampler.storageEntryCount, 2)
    for _ in 0..<100 {
      XCTAssertEqual(try quoteID(sampler.next(randomIndex: { _ in 0 })), "101")
    }
    let json = WebsiteConfigJSONWriter.write(.object(["quoteLength": draft.websiteValue]))
    let restored = try WebsiteConfigJSONReader.read(json)
    XCTAssertEqual(try WebsiteConfigNativeQuoteSelection(runtime: try XCTUnwrap(restored.importFields)), draft)
    XCTAssertEqual(QuoteLengthSelection.normalized([]), QuoteLengthSelection.selectable)
  }

  func testRequiredArrayRejectsMalformedGroupsWithoutRepair() throws {
    XCTAssertThrowsError(try WebsiteConfigNativeQuoteSelection(runtime: [:])) {
      XCTAssertEqual($0 as? WebsiteConfigNativeQuoteSelectionError, .missingField)
    }
    for value: WebsiteConfigValue in [.null, .number(1), .string("1"), .array([.number(-1)]),
      .array([.number(4)]), .array([.number(0.5)]), .array([.number(.infinity)]), .array([.string("0")])] {
      XCTAssertThrowsError(try WebsiteConfigNativeQuoteSelection(runtime: ["quoteLength": value])) {
        XCTAssertEqual($0 as? WebsiteConfigNativeQuoteSelectionError, .invalidField)
      }
    }
  }

  func testPinnedQuoteControllerAndGeneratorSelectionOutcomes() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let groups: [Int], pool: [String], draws: [String], failure: String?, recovery: [String: WebsiteConfigValue]
      let selectedQuoteID: String?, favoriteIDs: [String]?, randomLast: Bool?, emptyCatalog: Bool?
    }
    struct FailedDrawProgress: Decodable {
      let indices: [Int], failures: [String], continuedIndex: Int, uniqueDraws: Int
    }
    struct Output: Decodable { let fixtures: [Fixture]; let failedDrawProgress: FailedDrawProgress }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-quote-selection.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.failedDrawProgress.indices, [1, 2, 3])
    XCTAssertEqual(output.failedDrawProgress.failures, Array(repeating: "Random word is empty", count: 3))
    XCTAssertEqual(output.failedDrawProgress.continuedIndex, 4)
    XCTAssertEqual(output.failedDrawProgress.uniqueDraws, 4)
    let fixtures = output.fixtures
    XCTAssertEqual(fixtures.count, 1562)
    for (index, fixture) in fixtures.enumerated() {
      let selection = try Self.selection(fixture.groups)
      var sampler = try WebsiteQuoteSampler(selection: selection, quotes: fixture.emptyCatalog == true ? [] : Self.quotes)
      let random: (Int) -> Int = { fixture.randomLast == true ? $0 - 1 : 0 }
      var actual: [String] = []
      for _ in fixture.draws {
        actual.append(try quoteID(sampler.next(selectedQuoteID: fixture.selectedQuoteID,
          favoriteIDs: fixture.favoriteIDs, randomIndex: random)))
      }
      if selection.route == .lengths, !fixture.draws.isEmpty {
        XCTAssertEqual(sampler.cycleSize, fixture.pool.count, "fixture \(index)")
        let size = fixture.pool.count
        XCTAssertGreaterThan(size, 0)
        for start in stride(from: 0, to: actual.count, by: size) {
          XCTAssertEqual(counts(Array(actual[start..<(start + size)])), counts(fixture.pool), "native cycle \(index)")
          XCTAssertEqual(counts(Array(fixture.draws[start..<(start + size)])), counts(fixture.pool), "source cycle \(index)")
        }
      } else { XCTAssertEqual(actual, fixture.draws, "fixture \(index)") }
      if let failure = fixture.failure {
        let outcome = try sampler.next(selectedQuoteID: fixture.selectedQuoteID,
          favoriteIDs: fixture.favoriteIDs, randomIndex: random)
        guard case .unavailable(let reason, let recovery) = outcome else {
          XCTFail("Expected source failure \(failure), fixture \(index)"); continue
        }
        XCTAssertEqual(recovery.websiteChanges, fixture.recovery, "fixture \(index)")
        if failure == "No favorite quotes found" { XCTAssertEqual(reason, .favoriteQuoteUnavailable) }
        else if failure == "No quotes found for selected quote length" { XCTAssertEqual(reason, .noSelectedLengthQuotes) }
        else if failure.hasPrefix("Quote ") { XCTAssertEqual(reason, .selectedQuoteUnavailable) }
        else { XCTAssertEqual(reason, .noLanguageQuotes) }
      } else { XCTAssertTrue(fixture.recovery.isEmpty) }
      XCTAssertEqual(sampler.selection, selection)
    }
    print("Pinned quote selection/controller outcome fixtures: \(fixtures.count)")
  }

  @MainActor
  func testWebsiteGroupsRetainDuplicatesEmptyAndRoutePrecedence() throws {
    let cases: [([Int], WebsiteConfigNativeQuoteSelection.Route)] = [
      ([0, 0, 1], .lengths), ([], .lengths), ([-2], .selectedQuote),
      ([-2, -2], .lengths), ([-2, -3, 0], .favorites), ([-3, -3], .favorites), ([3, -2, 0], .lengths)
    ]
    for (groups, route) in cases {
      let value = WebsiteConfigValue.array(groups.map { .number(Double($0)) })
      let runtime = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(.object(["quoteLength": value])),
        context: .init()).projection.runtime
      XCTAssertEqual(runtime["quoteLength"], value)
      let draft = try WebsiteConfigNativeQuoteSelection(runtime: runtime)
      XCTAssertEqual(draft.groups, groups)
      XCTAssertEqual(draft.route, route)
      XCTAssertEqual(draft.websiteValue, value)
    }
  }
}
