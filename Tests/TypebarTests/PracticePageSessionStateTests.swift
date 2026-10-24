import Darwin
import TypebarSystem
import XCTest
@testable import Typebar

@MainActor final class PracticePageSessionStateTests: XCTestCase {
  private enum Failure: Error { case commit }
  @MainActor private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-page-state-\(UUID())")
    let owner = UUID(), router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    lazy var coordinator = makeCoordinator()
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("Page adoption must not write legacy settings") })
    }
    func makeCoordinator() -> WebsiteConfigCommitCoordinator {
      let epoch = UUID()
      return .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    }
    func publish(_ json: String = #"{"mode":"custom"}"#,
      using supplied: WebsiteConfigCommitCoordinator? = nil) async throws -> WebsiteConfigPublishedPresentation {
      let coordinator = supplied ?? coordinator
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab"))
      guard case .committed(let value) = try coordinator.commit(ready) else { throw Failure.commit }
      return try .init(publication: value, owner: owner, systemIsDark: false)
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
  }
  func testAdoptionOwnsThePreparedSessionScopeAndResourcesAsOneValueAndDuplicateKeepsTyping() async throws {
    let f = try Fixture(); defer { f.close() }
    let presentation = try await f.publish(#"{"mode":"custom","funbox":["rot13"]}"#)
    let original = PracticePageSessionState()
    var applied = try original.applying(presentation, owner: f.owner, router: f.router)
    XCTAssertEqual(applied.session.automaticInputAttemptID, presentation.publication.practice?.session.automaticInputAttemptID)
    XCTAssertEqual(applied.session.prompt, "no")
    XCTAssertEqual(applied.practice?.scope.customText, "ab")
    XCTAssertTrue(applied.presentation === presentation)
    XCTAssertNil(original.practice); XCTAssertNil(original.presentation)
    applied.session.insert("n")
    let duplicate = try applied.applying(presentation, owner: f.owner, router: f.router)
    XCTAssertEqual(duplicate.session.typed, "n")
    XCTAssertEqual(duplicate.session.automaticInputAttemptID, applied.session.automaticInputAttemptID)
  }
  func testForeignWindowRouterAndOwnerABACannotAdoptACommittedAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let p = try await f.publish(), state = PracticePageSessionState()
    XCTAssertThrowsError(try state.applying(p, owner: UUID(), router: f.router))
    let otherRouter = PreferenceConfigurationSaveRouter()
    otherRouter.register(owner: f.owner, save: {})
    XCTAssertThrowsError(try state.applying(p, owner: f.owner, router: otherRouter))
    let other = UUID(); f.router.register(owner: other, save: {})
    f.router.activate(owner: other); f.router.activate(owner: f.owner)
    XCTAssertThrowsError(try state.applying(p, owner: f.owner, router: f.router))
    XCTAssertNil(state.practice)
  }
  func testSupersededPublicationAndASeparateWriterCannotDeliverOldStateEvenWithIdenticalConfig() async throws {
    let f = try Fixture(); defer { f.close() }
    let first = try await f.publish(), second = try await f.publish()
    let state = PracticePageSessionState()
    XCTAssertThrowsError(try state.applying(first, owner: f.owner, router: f.router))
    _ = try state.applying(second, owner: f.owner, router: f.router)
    let other = f.makeCoordinator()
    let third = try await f.publish(using: other)
    XCTAssertThrowsError(try state.applying(second, owner: f.owner, router: f.router))
    XCTAssertEqual(try state.applying(third, owner: f.owner, router: f.router).session.automaticInputAttemptID,
      third.publication.session?.automaticInputAttemptID)
  }
  func testBusyDeliveryDoesNotMutatePageAndCanBeExplicitlyRetried() async throws {
    let f = try Fixture(); defer { f.close() }
    let p = try await f.publish(), state = PracticePageSessionState()
    let lock = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(lock, 0); defer { Darwin.close(lock) }
    XCTAssertEqual(typebar_file_lock(lock, LOCK_EX | LOCK_NB), 0)
    XCTAssertThrowsError(try state.applying(p, owner: f.owner, router: f.router))
    XCTAssertNil(state.practice)
    XCTAssertEqual(typebar_file_lock(lock, LOCK_UN), 0)
    XCTAssertNotNil(try state.applying(p, owner: f.owner, router: f.router).practice)
  }
  func testNoQuitRejectsAnotherAttemptButNotAnIdempotentDelivery() async throws {
    let f = try Fixture(); defer { f.close() }
    let p = try await f.publish(#"{"mode":"custom","funbox":["no_quit"]}"#)
    var state = try PracticePageSessionState().applying(p, owner: f.owner, router: f.router)
    state.session.insert("a")
    XCTAssertEqual(try state.applying(p, owner: f.owner, router: f.router).session.typed, "a")
    let other = try await f.publish()
    XCTAssertThrowsError(try state.applying(other, owner: f.owner, router: f.router)) { error in
      guard case PracticePageSessionStateError.locked = error else { return XCTFail("Expected live No Quit admission") }
    }
    XCTAssertEqual(state.session.typed, "a")
  }
  func testResourceOnlyPublicationCannotImpersonateAnAppliedPractice() throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare("{}"), localFont: .absent, localBackground: .absent)
    guard case .committed(let value) = try f.coordinator.commit(resources) else { throw Failure.commit }
    let p = try WebsiteConfigPublishedPresentation(publication: value, owner: f.owner, systemIsDark: false)
    XCTAssertThrowsError(try PracticePageSessionState().applying(p, owner: f.owner, router: f.router))
  }
}
