import XCTest
@testable import Typebar

@MainActor final class WebsiteThresholdInputNotationTests: XCTestCase {
  func testPinnedMinimumSpeedInputTextAndAdmissionAcrossFiveUnits() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference and schema dependencies")
    }
    struct Case: Decodable {
      let unit: String, initialBits: String, initialText: String, convertedBits: String
      let canSubmit: Bool
    }
    struct Output: Decodable { let id: String; let initialCases: [Case] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--threshold-input-notation"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.id, "setMinWpmCustomSpeedCustom")
    XCTAssertEqual(output.initialCases.count, 1380)
    XCTAssertEqual(Set(output.initialCases.map(\.initialBits)).count, 276)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-threshold-notation-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = PreferenceConfigurationSaveRouter(), owner = UUID(), epoch = UUID()
    router.register(owner: owner, save: { XCTFail("Website input must not save legacy preferences") })
    let coordinator = WebsiteConfigCommitCoordinator(router: router, register: .init(directory: directory),
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    for f in output.initialCases {
      let unit = try XCTUnwrap(TypingSpeedUnit(rawValue: f.unit))
      let initial = Double(bitPattern: try XCTUnwrap(UInt64(f.initialBits, radix: 16)))
      let converted = WebsiteThresholdCommandInput.toWpm(WebsiteThresholdCommandInput.number(f.initialText), unit: unit)
      XCTAssertEqual(converted.bitPattern, try XCTUnwrap(UInt64(f.convertedBits, radix: 16)))
      XCTAssertEqual(WebsiteThresholdCommandForm(text: f.initialText, target: .minimumWpmCustom, unit: unit).canSubmit, f.canSubmit)
      let literal = initial == .infinity ? "1e999" : (initial == 0 && initial.sign == .minus ? "-0" : f.initialText)
      do {
        let prepared = try coordinator.prepare("{\"minWpm\":\"custom\",\"minWpmCustomSpeed\":\(literal),\"typingSpeedUnit\":\"\(f.unit)\"}")
        guard case .committed(let publication) = try coordinator.commit(prepared) else { return XCTFail("Expected profile publication") }
        let presentation = try XCTUnwrap(WebsiteThresholdCommandPresentation(publication: publication, target: .minimumWpmCustom))
        XCTAssertEqual(presentation.unit, unit)
        XCTAssertEqual(presentation.initialText, f.initialText, "Input text \(f.initialBits)/\(f.unit)")
        XCTAssertEqual(publication.draft.inputRules.rules.minimumWpm.bitPattern, initial.bitPattern)
        guard let edit = WebsiteThresholdCommandInput.edits(for: .minimumWpmCustom, raw: presentation.initialText, unit: unit)?.first else {
          return XCTFail("Source-admitted input must prepare an edit")
        }
        let edited = try WebsiteConfigRuntimeProjector.edit(current: publication.draft.projection.runtime,
          key: edit.key, value: edit.value, defaults: WebsiteConfigNativeProfile.defaultDocument().values,
          schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: .init(), testActive: false)
        XCTAssertTrue(edited.rejectedKeys.isEmpty)
        let rules = try WebsiteConfigNativeInputRules(runtime: edited.runtime)
        XCTAssertEqual(rules.rules.minimumWpm.bitPattern, converted.bitPattern)
      } catch { XCTFail("Source-admitted threshold \(f.initialBits)/\(f.unit): \(error)") }
    }
  }

  func testInfiniteSpeedMemoriesReachLiveRulesWithoutChangingLegacyAdmission() throws {
    let start = Date(timeIntervalSince1970: 100)
    for mode in ["off", "custom"] {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"minWpm\":\"\(mode)\",\"minWpmCustomSpeed\":1e999}", pointsPerRem: 16, context: .init())
      XCTAssertEqual(draft.inputRules.rules.thresholdSource?.configuration.minimumWpmCustomValue, .infinity)
      var session = TypingSession(configuration: .words(6), prompt: "aaaa aaaa aaaa aaaa aaaa aaaa")
      session.insert("aaaa aaaa aaaa ", at: start)
      session.synchronizeLiveInputRules(draft.inputRules.rules)
      XCTAssertEqual(session.configuration.rules.minimumWpm, 0, "Legacy synchronization retains finite-only admission")
      session.synchronizeWebsiteInputRules(draft.inputRules.rules)
      XCTAssertEqual(session.configuration.rules.minimumWpm, mode == "off" ? 0 : .infinity)
      session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, .active, "Three committed words are not enough")
      session.insert("aaaa ", at: start.addingTimeInterval(1))
      session.enforceLivePracticeThresholds(at: start.addingTimeInterval(2))
      XCTAssertEqual(session.outcome, mode == "off" ? .active : .failed)
      XCTAssertEqual(session.failureReason, mode == "off" ? nil : .minimumWpm)
    }
    var legacy = PracticeThresholdConfiguration()
    XCTAssertThrowsError(try legacy.apply(.minimumWpm(mode: .custom, customValue: .infinity)))
    XCTAssertEqual(InputRules(minimumWpm: .infinity).minimumWpm, 0)
  }

  func testInfiniteBurstMemoriesDriveFixedAndFlexWordCommitChecks() throws {
    let start = Date(timeIntervalSince1970: 100)
    for mode in ["off", "fixed", "flex"] {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"minBurst\":\"\(mode)\",\"minBurstCustomSpeed\":1e999}", pointsPerRem: 16, context: .init())
      XCTAssertEqual(draft.inputRules.rules.thresholdSource?.configuration.minimumWordBurstCustomValue, .infinity)
      var session = TypingSession(configuration: .words(3), prompt: "amber bay cedar")
      session.insert("a", at: start)
      session.synchronizeWebsiteInputRules(draft.inputRules.rules)
      session.insert("mber ", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, mode == "off" ? .active : .failed)
      XCTAssertEqual(session.wordBurstHistory, [72])
      XCTAssertNil(session.failureReason, "Burst failure uses the existing generic failure path")
    }
  }

  func testWebsiteSpeedAdmissionKeepsTheExistingLiveRuleBoundary() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"strictSpace":true,"stopOnError":"letter","codeUnindentOnBackspace":true,"blindMode":true,"minWpm":"custom","minWpmCustomSpeed":1e999}"#,
      pointsPerRem: 16, context: .init())
    var session = TypingSession(configuration: .words(3), prompt: "ab cd ef")
    session.synchronizeLiveInputRules(draft.inputRules.rules, websiteThresholds: true)
    XCTAssertEqual(session.configuration.rules.minimumWpm, .infinity)
    XCTAssertTrue(session.configuration.rules.blindMode)
    XCTAssertFalse(session.configuration.rules.strictSpace)
    XCTAssertEqual(session.configuration.rules.stopOnErrorMode, .off)
    XCTAssertFalse(session.configuration.rules.codeUnindentOnBackspace)
  }
}
