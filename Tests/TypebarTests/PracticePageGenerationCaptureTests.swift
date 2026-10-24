import XCTest
@testable import Typebar

@MainActor final class PracticePageGenerationCaptureTests: XCTestCase {
  private enum Failure: Error { case notCommitted }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-generation-capture-\(UUID())")
    let register: WebsiteConfigFileRegister
    var environmentRevision = UUID()
    lazy var coordinator: WebsiteConfigCommitCoordinator = {
      return .init(router: router, register: register,
        environment: { [unowned self] in .init(revision: environmentRevision, context: .init(), pointsPerRem: 16) })
    }()
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("No legacy save") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func publish() async throws -> WebsiteConfigCommitCoordinator.Publication {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom"}"#),
        localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"))
      guard case .committed(let publication) = try coordinator.commit(ready, to: page, systemIsDark: true) else { throw Failure.notCommitted }
      return publication
    }
    func resources() throws -> WebsiteConfigCommitCoordinator.ResourcesPrepared {
      let ticket = try coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: page)
      return try coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    }
    func input(_ text: String) {
      var state = page.state
      state.session.insert(text, at: Date(timeIntervalSinceReferenceDate: 900_000_000))
      page.replace(state)
    }
  }

  func testCaptureUsesCurrentBooksAndKeepsScopedTextAndParameterMemories() async throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try await f.publish()
    var state = f.page.state
    var book = state.session.liveWeakSpotScores
    book.record(character: "z", interval: 0.7, isCorrect: false)
    state.session = state.session.withWeakSpotScores(book).withWordDecorationState(.init(spanishClosing: "!"))
    f.page.replace(state)
    let ready = try await f.coordinator.preparePractice(for: f.resources())
    XCTAssertEqual(ready.practice?.scope.customText, "ab cd")
    XCTAssertEqual(ready.session.liveWeakSpotScores, book)
    XCTAssertEqual(ready.practice?.scope.decorationState, .init(spanishClosing: "!"))
    XCTAssertEqual(ready.practice?.parameterMemory.duration, publication.practice?.parameterMemory.duration)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else { return XCTFail("Bound commit failed") }
    XCTAssertEqual(f.page.state.session.liveWeakSpotScores, book)
  }

  func testInputAfterCaptureRejectsBeforeDurableWriteAndKeepsCurrentInput() async throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try await f.publish()
    let ready = try await f.coordinator.preparePractice(for: f.resources())
    f.input("a")
    guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else { return XCTFail("Old scope overwrote input") }
    XCTAssertEqual(try f.register.read().revision, publication.disk)
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testInputDuringResourceReadStopsBeforeNextReader() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let ticket = try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.page)
    do {
      _ = try await f.coordinator.prepareResources(for: ticket,
        readLocalFont: { f.input("a"); return .absent },
        readLocalBackground: { XCTFail("Stale page continued reads"); return .absent })
      XCTFail("Changed source page admitted")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
  }

  func testDetachReattachAndForeignOrRecordOnlyDestinationsCannotBypassCapture() async throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try await f.publish()
    let ready = try await f.coordinator.preparePractice(for: f.resources())
    XCTAssertThrowsError(try f.coordinator.commit(ready))
    let other = PracticePageSessionStore(); other.attach(to: f.router)
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: other, systemIsDark: true))
    f.page.detach(); f.page.attach(to: f.router)
    guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else { return XCTFail("Attachment ABA revived capture") }
    XCTAssertEqual(try f.register.read().revision, publication.disk)
  }

  func testClockOnlyUpdatesDoNotRetireScopeButBookAndVisibleInputABAChangesDo() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let clock = PaceCaretTestClock()
    var paced = f.page.state
    paced.session.configurePace(wpm: 60, clock: clock.source)
    f.page.replace(paced)
    f.input("a")
    let capture = try f.page.captureGeneration(router: f.router)
    var state = f.page.state
    clock.time = 0.1
    XCTAssertTrue(state.session.tick(), "Exercise real pace progress, not a no-op tick")
    f.page.replace(state)
    XCTAssertTrue(f.page.isCurrent(capture, router: f.router))
    state = f.page.state
    state.session.insert("b", at: Date(timeIntervalSinceReferenceDate: 900_000_002))
    state.session.deleteBackward(at: Date(timeIntervalSinceReferenceDate: 900_000_003))
    f.page.replace(state)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertFalse(f.page.isCurrent(capture, router: f.router), "Equal visible text does not undo input activity")
  }

  func testBoundPreparationCannotUseAnArbitrarySessionProducerOrForeignScope() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let resources = try f.resources()
    let original = try await f.coordinator.preparePractice(for: resources)
    do {
      _ = try await f.coordinator.prepareSession(for: resources) { _ in
        XCTFail("Bound capture reached an arbitrary producer")
        return TestSessionFactory.make(configuration: .words(3))
      }
      XCTFail("Arbitrary producer admitted")
    } catch WebsiteConfigCommitCoordinatorError.sessionNotReady {}
    guard case .stale = try f.coordinator.commit(original, to: f.page, systemIsDark: true) else {
      return XCTFail("A forbidden new producer left the previous seed usable")
    }
    do {
      _ = try await f.coordinator.preparePractice(for: resources, scope: .init(customText: "foreign"))
      XCTFail("Foreign scope admitted")
    } catch WebsiteConfigCommitCoordinatorError.sessionNotReady {}
  }

  func testCompositionActivityInvalidatesCurrentCaptureButNotFromAnOldAttemptCallback() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    f.input("a")
    let capture = try f.page.captureGeneration(router: f.router)
    f.page.noteCompositionActivity(for: UUID())
    XCTAssertTrue(f.page.isCurrent(capture, router: f.router))
    f.page.noteCompositionActivity(for: f.page.state.session.automaticInputAttemptID)
    XCTAssertFalse(f.page.isCurrent(capture, router: f.router))
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testNewEnvironmentEpochRequiresFreshContentScopeInsteadOfReusingOldOwnerData() async throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try await f.publish()
    f.environmentRevision = UUID()
    XCTAssertThrowsError(try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.page),
      "A fresh environment is not evidence that the old content scope belongs to its account/resource owners")
    XCTAssertEqual(try f.register.read().revision, publication.disk)
    XCTAssertEqual(f.page.state.practice?.scope.customText, "ab cd")
  }
}
