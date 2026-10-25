import Foundation
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigPracticeBuildTransactionTests: XCTestCase {
  private enum Failure: Error { case notCommitted, read, gateNotEntered }
  @MainActor private final class Fixture {
    let directory: URL
    let owner = UUID()
    let router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    var environment = WebsiteConfigCommitCoordinator.Environment(revision: UUID(), context: .init(), pointsPerRem: 16)
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in self.environment })
    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-practice-build-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("Builder must not write legacy preferences") })
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
    func resources(_ json: String) throws -> WebsiteConfigCommitCoordinator.ResourcesPrepared {
      try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
    }
  }
  @MainActor private final class Gate {
    var pending: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { pending = $0 } }
    func release() { let old = pending; pending = nil; old?.resume() }
    func entered() async throws {
      for _ in 0..<1000 where pending == nil { await Task.yield() }
      guard pending != nil else { throw Failure.gateNotEntered }
    }
  }
  private func success(_ result: WebsiteConfigCommitCoordinator.Outcome) throws -> WebsiteConfigCommitCoordinator.Publication {
    guard case .committed(let value) = result else { throw Failure.notCommitted }; return value
  }
  func testRealBuildMetadataAndSessionPublishTogetherWithoutPersistingScopedText() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.coordinator.preparePractice(for: f.resources(
      #"{"mode":"custom","time":47,"words":83,"difficulty":"expert","funbox":["ddoouubblleedd","ddoouubblleedd","rot13"]}"#),
      scope: .init(customText: "ab"))
    XCTAssertNil(f.coordinator.publication(for: f.owner))
    XCTAssertEqual(try f.register.read().state, .missing)
    let published = try success(f.coordinator.commit(ready))
    let practice = try XCTUnwrap(published.practice)
    XCTAssertEqual(published.session?.automaticInputAttemptID, practice.session.automaticInputAttemptID)
    XCTAssertEqual(practice.session.prompt, "nnnnoooo")
    XCTAssertEqual(practice.scope.customText, "ab")
    XCTAssertEqual(practice.parameterMemory.duration, 47)
    XCTAssertEqual(practice.parameterMemory.wordLimit, 83)
    XCTAssertEqual(try f.register.read().state, .available(published.draft.projection.runtime))
    XCTAssertNil(published.draft.projection.runtime["customText"])
  }

  func testFullImportResetsQueueWhileOrdinaryNextBuildContinuesAndConflictCannotInstallCandidate() async throws {
    let f = try Fixture(); defer { f.close() }
    let json = #"{"mode":"quote","quoteLength":[0,0,1]}"#
    let draft = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
    let quotes = [OfflineQuote(id: "s", title: "Owned short", text: "ab", language: .english, length: .short),
      .init(id: "m", title: "Owned medium", text: "cd", language: .english, length: .medium)]
    let random = WebsiteConfigSessionBuilder.Random(quoteIndex: { _ in 0 })
    var scope = WebsiteConfigSessionBuilder.Scope()
    for _ in 0..<2 {
      scope = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: scope,
        loadQuotes: { _ in quotes }, random: random).scope
    }
    let continuing = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: scope,
      loadQuotes: { _ in quotes }, random: random)
    XCTAssertEqual(continuing.quote?.id, "m")
    let ready = try await f.coordinator.preparePractice(for: f.resources(json), scope: scope,
      loadQuotes: { _ in quotes }, random: random)
    let published = try success(f.coordinator.commit(ready))
    XCTAssertEqual(published.practice?.quote?.id, "s")
    let candidate = try await f.coordinator.preparePractice(for: f.resources(json), scope: continuing.scope,
      loadQuotes: { _ in quotes }, random: random)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":43}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try f.register.commit(external, replacing: published.disk) else { return XCTFail("External fixture failed") }
    guard case .conflict = try f.coordinator.commit(candidate) else { return XCTFail("Ignored conflict") }
    XCTAssertEqual(f.coordinator.publication(for: f.owner)?.applicationID, published.applicationID)
    let next = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
      scope: XCTUnwrap(f.coordinator.publication(for: f.owner)?.practice?.scope), loadQuotes: { _ in quotes }, random: random)
    XCTAssertEqual(next.quote?.id, "s")
  }

  func testLateReaderFailureIsStaleAfterEnvironmentChangeAndCannotCommitRecovery() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources(#"{"mode":"quote"}"#)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in
        f.environment = .init(revision: UUID(), context: .init(), pointsPerRem: 16)
        await Task.yield(); throw Failure.read
      })
      XCTFail("Late reader error escaped freshness check")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertNil(f.coordinator.publication(for: f.owner))
    let fresh = try f.resources(#"{"mode":"quote"}"#)
    let recovered = try await f.coordinator.preparePractice(for: fresh, scope: .init(), loadQuotes: { _ in [] })
    XCTAssertEqual(recovered.session.configuration.mode, .words)
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertNil(f.coordinator.publication(for: f.owner), "Preparation is still not a publication or disk commit")
  }

  func testStandaloneBuilderCancellationWinsOverIgnoredCancellationAndLateReadError() async throws {
    let gate = Gate(); defer { gate.release() }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"quote"}"#, pointsPerRem: 16, context: .init())
    let pending = Task { @MainActor in
      _ = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(), loadQuotes: { _ in
        await gate.wait(); throw Failure.read
      })
    }
    defer { pending.cancel() }
    try await gate.entered(); pending.cancel(); gate.release()
    do { try await pending.value; XCTFail("Cancelled builder forwarded a read error") } catch is CancellationError {}
  }
}
