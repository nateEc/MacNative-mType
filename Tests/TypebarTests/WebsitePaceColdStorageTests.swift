import XCTest
@testable import Typebar

@MainActor final class WebsitePaceColdStorageTests: XCTestCase {
  func testActualPinnedStorageMigrationAgainstNativeEffectiveColdValues() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference and schema dependencies")
    }
    struct Fixture: Decodable {
      let mode: String, warmBits: String, coldBits: String
      let persistedNull: Bool, unrelatedKeysPreserved: Bool, warmCachePreserved: Bool
      let writes: Int
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--pace-storage"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 8)
    for f in output.fixtures {
      let speed = Double(bitPattern: try XCTUnwrap(UInt64(f.warmBits, radix: 16)))
      var warm = try WebsiteConfigNativeProfile.prepare(#"{"words":77,"numbers":true,"typingSpeedUnit":"cpm","paceCaretStyle":"off"}"#,
        context: .init()).projection.runtime
      warm["paceCaret"] = .string(f.mode); warm["paceCaretCustomSpeed"] = .number(speed)
      let bytes = try WebsiteConfigNativeStateCodec.encode(warm)
      let decoded = try WebsiteConfigNativeStateCodec.decode(bytes)
      XCTAssertEqual(decoded, warm)
      guard case .prepared(let cold) = try WebsiteConfigNativeProfile.prepareNativeRestoration(.available(decoded), context: .init()) else {
        return XCTFail("Expected native cold preparation")
      }
      let restored = Double(bitPattern: try XCTUnwrap(UInt64(f.coldBits, radix: 16)))
      var expected = warm; expected["paceCaretCustomSpeed"] = .number(restored)
      XCTAssertEqual(cold.projection.runtime, expected)
      XCTAssertEqual(cold.loaded, warm)
      XCTAssertEqual(f.persistedNull, speed == .infinity)
      XCTAssertEqual(f.writes, speed == .infinity ? 2 : 1)
      XCTAssertTrue(f.unrelatedKeysPreserved); XCTAssertTrue(f.warmCachePreserved)
      XCTAssertEqual(try WebsiteConfigNativeStateCodec.encode(warm), bytes, "Cold preparation is not an archive write")
    }
  }

  func testColdCorrectionCommitsOnlyThroughTheCurrentFileRevision() throws {
    for outcome in ["commit", "conflict", "unsafe-lock"] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-pace-cold-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), epoch = UUID()
      router.register(owner: owner, save: { XCTFail("Do not change legacy preferences") })
      let register = WebsiteConfigFileRegister(directory: directory)
      let warmCoordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
      guard case .committed(let warm) = try warmCoordinator.commit(warmCoordinator.prepare(
        #"{"paceCaret":"custom","paceCaretCustomSpeed":1e999,"words":77,"numbers":true,"typingSpeedUnit":"cpm"}"#)) else {
        return XCTFail("Expected warm publication")
      }
      let record = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      let originalBytes = try Data(contentsOf: record)
      let coldCoordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
      guard case .prepared(let cold) = try coldCoordinator.prepareRestoration() else { return XCTFail("Expected cold ticket") }
      XCTAssertEqual(cold.draft.behavior.paceGuideCustomWpm, 100)
      XCTAssertEqual(try Data(contentsOf: record), originalBytes)
      switch outcome {
      case "commit":
        guard case .committed(let restored) = try coldCoordinator.commit(cold) else { return XCTFail("Expected cold commit") }
        var expected = warm.draft.projection.runtime; expected["paceCaretCustomSpeed"] = .number(100)
        XCTAssertEqual(restored.draft.projection.runtime, expected)
        XCTAssertEqual(try register.read().state, .available(expected))
        XCTAssertNotEqual(try Data(contentsOf: record), originalBytes)
      case "conflict":
        let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":88,"paceCaretCustomSpeed":120}"#,
          pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(other, replacing: XCTUnwrap(register.read().revision)) else {
          return XCTFail("Expected competing writer")
        }
        let otherBytes = try Data(contentsOf: record)
        guard case .conflict = try coldCoordinator.commit(cold) else { return XCTFail("Stale correction overwrote another writer") }
        XCTAssertEqual(try Data(contentsOf: record), otherBytes)
        XCTAssertNil(coldCoordinator.publication(for: owner))
      default:
        let lock = directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lock.path)
        XCTAssertThrowsError(try coldCoordinator.commit(cold))
        XCTAssertEqual(try Data(contentsOf: record), originalBytes)
        XCTAssertNil(coldCoordinator.publication(for: owner))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.path)
      }
      XCTAssertEqual(warm.draft.behavior.paceGuideCustomWpm, .infinity, "Old warm publication remains a value snapshot")
    }
  }
}
