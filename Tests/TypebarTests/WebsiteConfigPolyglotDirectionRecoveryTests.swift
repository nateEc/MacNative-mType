import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteConfigPolyglotDirectionRecoveryTests: XCTestCase {
  @MainActor private final class Once { var used = false }
  @MainActor private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-polyglot-recovery-\(UUID())")
    let router = PreferenceConfigurationSaveRouter(), owner = UUID(), environment = UUID()
    let register: WebsiteConfigFileRegister
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in .init(revision: self.environment, context: .init(), pointsPerRem: 16) })
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("No legacy preference writes") })
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
  }
  func testCompetingRecordDuringDirectionNoticeCannotBeReplacedByTheRetiredCandidate() async throws {
    let f = try Fixture(); defer { f.close() }
    let notices = LocalNoticeCenter(); defer { notices.clearAll() }
    let report = WebsiteConfigInitializationReport(notices: notices), once = Once()
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"time","time":89}"#, pointsPerRem: 16, context: .init())
    withObservationTracking { _ = notices.history } onChange: {
      MainActor.assumeIsolated {
        guard !once.used else { return }; once.used = true
        do {
          guard case .committed = try f.register.commit(external, replacing: XCTUnwrap(f.register.read().revision)) else {
            return XCTFail("Competing write setup failed")
          }
        } catch { XCTFail("Competing write failed: \(error)") }
      }
    }
    let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare(
      #"{"mode":"words","words":2,"funbox":["polyglot"],"customPolyglot":["arabic","hebrew"]}"#),
      localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, scope: .init(), initializationReport: report)
      XCTFail("Competing record ignored")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertTrue(once.used)
    XCTAssertEqual(try f.register.read().state, .available(external.projection.runtime))
    XCTAssertNil(f.coordinator.publication(for: f.owner))
    XCTAssertTrue(notices.history.isEmpty)
  }
  func testPinnedInitAndWithWordsDirectionMatrixReachesActualNativePublication() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Notice: Decodable { let important: Bool; let duration: Int }
    struct Case: Decodable {
      let base: String, selected: [String], finalLanguage: String, writes: [String], notices: [Notice], calls: Int
    }
    struct Output: Decodable { let fixtures: [Case] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-polyglot-recovery.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 54)
    for fixture in fixtures {
      let f = try Fixture(); defer { f.close() }
      let notices = LocalNoticeCenter(); defer { notices.clearAll() }
      let report = WebsiteConfigInitializationReport(notices: notices)
      let base = try XCTUnwrap(WebsiteLanguageIdentity.language(for: fixture.base))
      let selected = try fixture.selected.map { try XCTUnwrap(WebsiteLanguageIdentity.language(for: $0)) }
      let expected = try XCTUnwrap(WebsiteLanguageIdentity.language(for: fixture.finalLanguage))
      XCTAssertEqual(PolyglotGenerationPreparation.directionFallback(primary: base, selected: selected).flatMap(WebsiteLanguageIdentity.name), fixture.writes.first)
      let json = WebsiteConfigJSONWriter.write(.object(["mode": .string("words"), "words": .number(2),
        "language": .string(fixture.base), "funbox": .array([.string("polyglot")]),
        "customPolyglot": .array(fixture.selected.map(WebsiteConfigValue.string))]))
      let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await f.coordinator.preparePractice(for: resources, scope: .init(), initializationReport: report,
        random: .init(wordIndex: { 0 }, contentUnit: { 0.25 }, shuffleIndex: { $0 - 1 }))
      XCTAssertEqual(ready.session.configuration.polyglotBaseLanguage, expected)
      XCTAssertEqual(ready.session.configuration.mixedLanguageComponents, selected)
      XCTAssertEqual(report.failures.count, fixture.calls - 1)
      XCTAssertTrue(report.failures.allSatisfy { $0.message.isEmpty })
      XCTAssertNil(report.finalMessage)
      XCTAssertEqual(notices.history.count, fixture.notices.count)
      XCTAssertTrue(notices.history.allSatisfy { $0.level == .notice })
      XCTAssertTrue(notices.active.allSatisfy { !$0.important && $0.durationMilliseconds == 5000 })
      XCTAssertTrue(fixture.notices.allSatisfy { !$0.important && $0.duration == 5000 })
      guard case .committed(let publication) = try f.coordinator.commit(ready) else { return XCTFail("Native publication rejected") }
      XCTAssertEqual(publication.draft.testParameters.language, expected)
      guard case .available(let saved) = try f.register.read().state else { return XCTFail("Missing saved configuration") }
      XCTAssertEqual(saved["language"], .string(fixture.finalLanguage))
    }
  }
}
