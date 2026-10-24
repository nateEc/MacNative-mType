import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigApplicationQueueTests: XCTestCase {
  private let json = #"{"mode":"quote","quoteLength":[0,0,1]}"#
  private var quotes: [OfflineQuote] {
    [("101", QuoteLength.short), ("102", .short), ("103", .medium)].map {
      .init(id: $0.0, title: "Owned event queue sample", text: "ab", language: .english, length: $0.1)
    }
  }
  private func draft() throws -> WebsiteConfigNativeDraft {
    try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
  }
  private func advancedScope(_ draft: WebsiteConfigNativeDraft) async throws -> WebsiteConfigSessionBuilder.Scope {
    var scope = WebsiteConfigSessionBuilder.Scope()
    for _ in 0..<2 {
      scope = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: scope,
        loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { _ in 0 })).scope
    }
    return scope
  }

  func testActualSourceEventsResetOnlyQuoteLengthEvenForSameValueAndNosave() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Application: Decodable { let key: String; let nosave: Bool; let before: Int; let remaining: Int }
    struct Output: Decodable { let applications: [Application] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-quote-selection.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let applications = try JSONDecoder().decode(Output.self, from: data).applications
    XCTAssertEqual(applications.count, 12)
    let original = try draft()
    let scope = try await advancedScope(original)
    for application in applications where !application.key.hasPrefix("fullConfig") {
      let value: WebsiteConfigValue
      switch application.key {
      case "soundVolume": value = .number(0.3)
      case "quoteLength": value = .array([.number(0), .number(0), .number(1)])
      default: value = .string(application.key == "mode" ? "quote" : "english")
      }
      let edited = try WebsiteConfigNativeProfile.editDraft(original, key: application.key, value: value,
        pointsPerRem: 16, context: .init(), nosave: application.nosave)
      var budget: Int?
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: edited, scope: scope,
        reason: .configurationApplication, loadQuotes: { _ in self.quotes },
        random: .init(quoteIndex: { budget = $0; return 0 }))
      XCTAssertEqual(application.before, 2)
      XCTAssertEqual(budget, application.remaining, "\(application.key), nosave \(application.nosave)")
    }
    XCTAssertTrue(applications.filter { $0.key.hasPrefix("fullConfig") }.allSatisfy { $0.remaining == 3 },
      "The full-config boundary events alone do not rebuild the source queue")
  }

  func testApplicationAndOrdinaryNextHaveDifferentQueueLifetimesAndRetryDoesNotConsumeScope() async throws {
    let original = try draft()
    let scope = try await advancedScope(original)
    for reason in [WebsiteConfigSessionBuilder.Reason.nextAttempt, .configurationApplication] {
      for _ in 0..<2 {
        var budget: Int?
        let candidate = try await WebsiteConfigSessionBuilder.prepare(draft: original, scope: scope, reason: reason,
          loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { budget = $0; return 0 }))
        XCTAssertEqual(budget, reason == .nextAttempt ? 3 : 5)
        var nextBudget: Int?
        _ = try await WebsiteConfigSessionBuilder.prepare(draft: original, scope: candidate.scope,
          loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { nextBudget = $0; return 0 }))
        XCTAssertEqual(nextBudget, reason == .nextAttempt ? 2 : 4,
          "An installed candidate advances once; ordinary next must not replay its import events")
      }
    }
    do {
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: original, scope: scope,
        reason: .configurationApplication, loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { $0 }))
      XCTFail("Invalid draw was admitted")
    } catch WebsiteConfigNativeQuoteSelectionError.invalidRandomIndex {}
    var budget: Int?
    _ = try await WebsiteConfigSessionBuilder.prepare(draft: original, scope: scope,
      loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 3)
  }

  func testNonQuoteApplicationCarriesOrInvalidatesDormantQueueFromActualSetterEvents() async throws {
    let original = try draft()
    let scope = try await advancedScope(original)
    let modeOnly = try WebsiteConfigNativeProfile.editDraft(original, key: "mode", value: .string("words"),
      pointsPerRem: 16, context: .init())
    let full = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","quoteLength":[0,0,1]}"#,
      pointsPerRem: 16, context: .init())
    for (change, expectedBudget) in [(modeOnly, 3), (full, 5)] {
      let nonQuote = try await WebsiteConfigSessionBuilder.prepare(draft: change, scope: scope,
        reason: .configurationApplication, loadQuotes: { _ in XCTFail("Words mode read quotes"); return [] })
      XCTAssertEqual(nonQuote.scope.quoteSampler == nil, expectedBudget == 5)
      let reenter = try WebsiteConfigNativeProfile.editDraft(change, key: "mode", value: .string("quote"),
        pointsPerRem: 16, context: .init())
      var budget: Int?
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: reenter, scope: nonQuote.scope,
        reason: .configurationApplication, loadQuotes: { _ in self.quotes },
        random: .init(quoteIndex: { budget = $0; return 0 }))
      XCTAssertEqual(budget, expectedBudget)
      XCTAssertEqual(nonQuote.parameterMemory.wordLimit, 50)
      XCTAssertEqual(nonQuote.parameterMemory.duration, 30)
    }
  }
}
