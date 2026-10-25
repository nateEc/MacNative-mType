import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigFunboxMemoryTests: XCTestCase {
  @MainActor private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-funbox-memory-\(UUID())")
    let owner = UUID(), revision = UUID(), router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in .init(revision: self.revision, context: .init(), pointsPerRem: 16) })
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory); router.register(owner: owner, save: { XCTFail("No legacy writes") })
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
    func deliver(_ prepared: WebsiteConfigCommitCoordinator.Prepared) async throws -> WebsiteConfigCommitCoordinator.Publication {
      let resources = try coordinator.prepareResources(for: prepared, localFont: .absent, localBackground: .absent)
      let session = try await coordinator.preparePractice(for: resources, scope: .init())
      guard case .committed(let value) = try coordinator.commit(session) else { throw WebsiteConfigCommitCoordinatorError.stale }
      return value
    }
  }
  func testClearingSimonSaysRestoresTheKeyboardSettingFromBeforeActivation() async throws {
    let f = try Fixture(); defer { f.close() }
    let selected = try await f.deliver(f.coordinator.prepare(#"{"mode":"words","words":4,"funbox":["simon_says"],"keymapMode":"off"}"#))
    XCTAssertEqual(selected.draft.keyboardTypography.guideMode, .next)
    let cleared = try await f.deliver(f.coordinator.prepareEdit(key: "funbox", value: .array([]), from: selected, testActive: false))
    XCTAssertEqual(cleared.draft.keyboardTypography.guideMode, .off)
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Missing configuration") }
    XCTAssertEqual(saved["keymapMode"], .string("off"))
  }
  func testCommandProposalsRemoveEveryMatchingNamePreserveRemainingOrderAndSortAdditions() throws {
    func draft(_ names: [String]) throws -> WebsiteConfigNativeDraft {
      try WebsiteConfigNativeProfile.prepareDraft(WebsiteConfigJSONWriter.write(.object([
        "mode": .string("words"), "words": .number(4), "funbox": .array(names.map(WebsiteConfigValue.string))
      ])), pointsPerRem: 16, context: .init())
    }
    let repeated = try draft(["rot13", "no_quit", "rot13"])
    XCTAssertEqual(WebsiteConfigFunboxMemory.proposal(for: .modifier(.rot13), in: repeated), ["no_quit"])
    let ordered = try draft(["rot13", "no_quit"])
    XCTAssertEqual(WebsiteConfigFunboxMemory.proposal(for: .modifier(.randomCase), in: ordered), ["no_quit", "rAnDoMcAsE", "rot13"])
    XCTAssertEqual(WebsiteConfigFunboxMemory.proposal(for: .clear, in: repeated), [])
    XCTAssertNil(WebsiteConfigFunboxMemory.proposal(for: .modifier(.listening), in: try draft(["simon_says"])))
  }
  func testRepeatedRestartsAndAnInterveningSavingSetterDoNotReplaceTheEarliestMemory() async throws {
    let f = try Fixture(); defer { f.close() }
    var current = try await f.deliver(f.coordinator.prepare(#"{"mode":"words","words":4,"funbox":["simon_says"],"keymapMode":"react"}"#))
    current = try await f.deliver(f.coordinator.prepareEdit(key: "words", value: .number(5), from: current, testActive: false))
    XCTAssertEqual(current.draft.keyboardTypography.guideMode, .next)
    guard case .available(let promoted) = try f.register.read().state else { return XCTFail("Missing saving setter") }
    XCTAssertEqual(promoted["keymapMode"], .string("next"))
    current = try await f.deliver(f.coordinator.prepareEdit(key: "funbox", value: .array([]), from: current, testActive: false))
    XCTAssertEqual(current.draft.keyboardTypography.guideMode, .react)
  }
}
