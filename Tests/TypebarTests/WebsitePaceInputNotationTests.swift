import XCTest
@testable import Typebar

@MainActor final class WebsitePaceInputNotationTests: XCTestCase {
  func testInfiniteCustomTargetStartsTheActualSessionCallbackChain() throws {
    let target = PaceGuidePolicy.targetWpm(mode: .custom, customWpm: .infinity,
      configuration: .words(10), samples: [])
    XCTAssertEqual(target, .infinity)
    var session = TypingSession(configuration: .words(10), prompt: "ab cd ef")
    session.configurePace(wpm: target)
    session.insertBatch("a", at: .now)
    XCTAssertNotNil(session.paceCaretPendingTicket)
    XCTAssertEqual(session.paceCaretFrame()?.target, .init(word: 0, letter: 1))
  }

  func testNativeColdRestoreNormalizesOnlyInfinitePaceWithoutMutatingWarmValues() throws {
    var warm = try WebsiteConfigNativeProfile.prepare(#"{"paceCaret":"custom","words":77,"numbers":true,"typingSpeedUnit":"cpm","paceCaretStyle":"off"}"#,
      context: .init()).projection.runtime
    warm["paceCaretCustomSpeed"] = .number(.infinity)
    let original = warm
    guard case .prepared(let cold) = try WebsiteConfigNativeProfile.prepareNativeRestoration(.available(warm), context: .init()) else {
      return XCTFail("Expected cold candidate")
    }
    var expected = warm; expected["paceCaretCustomSpeed"] = .number(100)
    XCTAssertEqual(cold.projection.runtime, expected)
    XCTAssertEqual(cold.loaded, original, "Raw native archive evidence remains available")
    XCTAssertEqual(warm, original, "Cold preparation does not mutate the warm session")
    XCTAssertNil(cold.websiteStorage, "Do not forge browser writes for native records")
  }

  func testPinnedInputTextConversionAndAdmissionAcrossFiveUnits() throws {
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
      reference, "--pace-input-notation"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.id, WebsitePaceSpeedPresentation.item.id)
    XCTAssertEqual(output.initialCases.count, 1380)
    XCTAssertEqual(Set(output.initialCases.map(\.initialBits)).count, 276)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pace-notation-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = PreferenceConfigurationSaveRouter(), owner = UUID(), epoch = UUID()
    router.register(owner: owner, save: { XCTFail("Command presentation must not save legacy preferences") })
    let coordinator = WebsiteConfigCommitCoordinator(router: router, register: .init(directory: directory),
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    for f in output.initialCases {
      let unit = try XCTUnwrap(TypingSpeedUnit(rawValue: f.unit))
      let value = Double(bitPattern: try XCTUnwrap(UInt64(f.initialBits, radix: 16)))
      let converted = try XCTUnwrap(WebsitePaceCommand.speed(f.initialText, unit: unit))
      XCTAssertEqual(converted.bitPattern, try XCTUnwrap(UInt64(f.convertedBits, radix: 16)), "\(f.initialBits)/\(f.unit)")
      XCTAssertEqual(WebsitePaceSpeedForm(text: f.initialText, unit: unit).canSubmit, f.canSubmit,
        "Source input admission: \(f.initialBits)/\(f.unit)")
      // JSON's exponent overflow supplies the same source-admissible Infinity;
      // -0 must retain its bit pattern before the input builder prints it as 0.
      let literal = value == .infinity ? "1e999" : (value == 0 && value.sign == .minus ? "-0" : f.initialText)
      do {
        let prepared = try coordinator.prepare("{\"paceCaret\":\"custom\",\"paceCaretCustomSpeed\":\(literal),\"typingSpeedUnit\":\"\(f.unit)\"}")
        guard case .committed(let publication) = try coordinator.commit(prepared) else {
          return XCTFail("Expected actual profile publication")
        }
        XCTAssertEqual(publication.draft.behavior.paceGuideCustomWpm.bitPattern, value.bitPattern)
        let presentation = WebsitePaceSpeedPresentation(publication: publication)
        XCTAssertEqual(presentation.unit, unit)
        XCTAssertEqual(presentation.initialText, f.initialText, "Input text for \(f.initialBits)/\(f.unit)")
        if f.canSubmit {
          XCTAssertNoThrow(try WebsitePaceCommand.plan(current: publication.draft.projection.runtime, target: .customSpeed,
            input: presentation.initialText, context: .init(), active: false), "Source-admitted input must prepare a command")
        }
      } catch { XCTFail("Source-admitted profile \(f.initialBits)/\(f.unit): \(error)") }
    }
  }
}
