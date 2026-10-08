import Foundation
import XCTest
@testable import Typebar

final class FriendNameValidationTests: XCTestCase {
  private func profile(_ name: String = "Target", id: UUID = UUID()) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: [
      "id": id.uuidString, "displayName": name, "joinedAt": 0, "completedResultCount": 0, "bestWPM": 0]))
  }
  @MainActor private func session(_ body: (AccountSession, ConnectionsManagementState, ConnectionsReadIdentity) async throws -> Void) async throws {
    let suite = "TypebarTests.friend-name.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owner", totalExperience: 0)
    let read = ConnectionsReadIdentity(owner: .init(account: account), account: account, refresh: UUID())
    let manager = ConnectionsManagementState()
    await manager.load(request: read, account: account) { .init(connections: [], blockedProfiles: []) }
    try await body(account, manager, read)
  }
  @MainActor private func id(_ name: String, _ read: ConnectionsReadIdentity, ready: Bool = true) -> FriendNameCheckID {
    .init(read: read, rawName: name, ownerName: "Owner", snapshotReady: ready)
  }

  func testNamesNormalizeOnlyWhitespaceAndUseServiceIdentityCollation() {
    XCTAssertEqual(FriendNamePolicy.normalized("  Target  "), "Target")
    XCTAssertEqual(FriendNamePolicy.normalized("A"), "A")
    XCTAssertEqual(FriendNamePolicy.normalized(String(repeating: "a", count: 32))?.count, 32)
    for name in ["", "   ", "A\nB", "A\u{2028}B", String(repeating: "a", count: 33)] { XCTAssertNil(FriendNamePolicy.normalized(name)) }
    XCTAssertEqual(FriendNamePolicy.key("RÉSUMÉ"), FriendNamePolicy.key("resume"))
  }

  @MainActor func testSelfInvalidAndEveryExistingDirectionRejectWithoutRemoteOrDebounce() async throws {
    try await session { account, manager, read in
      let state = FriendNameValidationState(); var calls = 0
      for name in ["", "Owner", "oWnEr", "A\nB"] {
        let id = self.id(name, read)
        await state.check(id, account: account, management: manager, debounce: { calls += 1 }, resolve: { _ in calls += 1; return nil })
        XCTAssertNil(state.readyProfile(id, account: account, management: manager))
      }
      for relation in [RemoteConnectionRelation.incomingRequest, .outgoingRequest, .friend] {
        let target = try self.profile()
        await manager.load(request: read, account: account) {
          .init(connections: [.init(id: target.id, profile: target, relation: relation, updatedAt: .now)], blockedProfiles: [])
        }
        let id = self.id("tArGeT", read)
        await state.check(id, account: account, management: manager, debounce: { calls += 1 }, resolve: { _ in calls += 1; return target })
        XCTAssertNil(state.readyProfile(id, account: account, management: manager))
        guard case .existing = state.status else { return XCTFail("Must show existing relationship") }
      }
      let blocked = try self.profile()
      await manager.load(request: read, account: account) { .init(connections: [], blockedProfiles: [blocked]) }
      await state.check(self.id("Target", read), account: account, management: manager, debounce: { calls += 1 }, resolve: { _ in calls += 1; return nil })
      guard case .existing(.blocked) = state.status else { return XCTFail("Must show own block") }
      XCTAssertEqual(calls, 0)
    }
  }

  @MainActor func testRemoteRunsOnlyAfterDebounceAndReadyUsesExactUUIDNotName() async throws {
    try await session { account, manager, read in
      let state = FriendNameValidationState(), id = self.id("Target", read), target = try self.profile()
      var delay: CheckedContinuation<Void, Never>?, calls = 0
      let task = Task { @MainActor in await state.check(id, account: account, management: manager,
        debounce: { await withCheckedContinuation { delay = $0 } }, resolve: { name in
          XCTAssertEqual(name, "Target"); calls += 1; return target
        }) }
      for _ in 0..<20 where delay == nil { await Task.yield() }
      XCTAssertNotNil(delay); XCTAssertEqual(calls, 0); XCTAssertNil(state.readyProfile(id, account: account, management: manager))
      delay?.resume(); await task.value
      XCTAssertEqual(calls, 1); XCTAssertEqual(state.readyProfile(id, account: account, management: manager)?.id, target.id)
      state.clear(); XCTAssertNil(state.readyProfile(id, account: account, management: manager))
    }
  }

  @MainActor func testInputABAAndLateErrorsCannotReplaceNewerReadyIdentity() async throws {
    try await session { account, manager, read in
      for fails in [false, true] {
        let state = FriendNameValidationState(), first = self.id("Target", read), target = try self.profile()
        var pending: CheckedContinuation<RemotePublicProfile?, Error>?
        let task = Task { @MainActor in await state.check(first, account: account, management: manager,
          debounce: {}, resolve: { _ in try await withCheckedThrowingContinuation { pending = $0 } }) }
        for _ in 0..<20 where pending == nil { await Task.yield() }
        XCTAssertNotNil(pending); state.clear()
        let newer = self.id("Target", read)
        await state.check(newer, account: account, management: manager, debounce: {}, resolve: { _ in target })
        if fails { pending?.resume(throwing: URLError(.timedOut)) } else { pending?.resume(returning: nil) }
        await task.value
        XCTAssertEqual(state.readyProfile(newer, account: account, management: manager)?.id, target.id)
        XCTAssertNil(state.readyProfile(first, account: account, management: manager))
      }
    }
  }

  @MainActor func testUnknownMalformedErrorAndRenamedExistingUUIDNeverEnableSubmission() async throws {
    try await session { account, manager, read in
      let state = FriendNameValidationState(), id = self.id("Target", read)
      await state.check(id, account: account, management: manager, debounce: {}, resolve: { _ in nil })
      guard case .unknown = state.status else { return XCTFail("Missing exact target must be unknown") }
      await state.check(id, account: account, management: manager, debounce: {}, resolve: { _ in try self.profile("WrongTarget") })
      guard case .failed = state.status else { return XCTFail("Mismatched target must fail") }
      await state.check(id, account: account, management: manager, debounce: {}, resolve: { _ in throw URLError(.badServerResponse) })
      guard case .failed = state.status else { return XCTFail("Legacy service/error must not be unknown user") }
      let renamed = try self.profile("OldName")
      await manager.load(request: read, account: account) {
        .init(connections: [.init(id: renamed.id, profile: renamed, relation: .friend, updatedAt: .now)], blockedProfiles: [])
      }
      await state.check(id, account: account, management: manager, debounce: {}, resolve: { _ in try self.profile("Target", id: renamed.id) })
      guard case .existing(.friend) = state.status else { return XCTFail("Current UUID relation survives rename") }
      XCTAssertNil(state.readyProfile(id, account: account, management: manager))
    }
  }

  @MainActor func testOwnerRevisionUnknownSnapshotAndRetiredWriteResultsStopLookupBeforeProvider() async throws {
    try await session { account, manager, read in
      let state = FriendNameValidationState(), id = self.id("Target", read); var calls = 0
      await state.check(self.id("Target", read, ready: false), account: account, management: manager,
        debounce: { calls += 1 }, resolve: { _ in calls += 1; return nil })
      XCTAssertEqual(calls, 0)
      await state.check(id, account: account, management: manager,
        debounce: { account.noteProfileRelationshipsChanged(identity: read.owner.owner) }, resolve: { _ in calls += 1; return nil })
      XCTAssertEqual(calls, 0); XCTAssertNil(state.readyProfile(id, account: account, management: manager))
      let latest = ConnectionsReadIdentity(owner: read.owner, account: account, refresh: UUID())
      await manager.load(request: latest, account: account) { .init(connections: [], blockedProfiles: []) }
      await state.check(self.id("Target", latest), account: account, management: manager,
        debounce: { _ = await manager.perform(.send(UUID()), request: latest, account: account) { throw URLError(.timedOut) } },
        resolve: { _ in calls += 1; return nil })
      XCTAssertEqual(calls, 0); XCTAssertNil(manager.snapshot)
      account.currentUser = nil
      do { _ = try await account.resolveFriendName("Target", identity: read.owner); XCTFail("Stale owner must reject before HTTP") }
      catch { XCTAssertFalse(read.owner.isCurrent(account)) }
    }
  }

  @MainActor func testNativeNamePreflightAvailabilityMatchesActualPinnedModalAndRemoteValidator() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned reference") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-add-friend.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable { let isSelf: Bool; let relation: String; let lookup: String; let valid: Bool; let remoteCalls: Int }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 50)
    for fixture in fixtures {
      try await session { account, manager, read in
        let target = try self.profile(), relation: RemoteConnectionRelation? = switch fixture.relation {
        case "outgoing": .outgoingRequest
        case "incoming": .incomingRequest
        case "friend": .friend
        default: nil
        }
        await manager.load(request: read, account: account) {
          .init(connections: relation.map { [.init(id: target.id, profile: target, relation: $0, updatedAt: .now)] } ?? [],
            blockedProfiles: fixture.relation == "blocked" ? [target] : [])
        }
        let state = FriendNameValidationState(), id = self.id(fixture.isSelf ? "Owner" : "Target", read)
        var calls = 0
        await state.check(id, account: account, management: manager, debounce: {}, resolve: { _ in
          calls += 1
          switch fixture.lookup {
          case "exists": return target
          case "unknown": return nil
          default: throw URLError(.badServerResponse)
          }
        })
        XCTAssertEqual(state.readyProfile(id, account: account, management: manager) != nil, fixture.valid)
        XCTAssertEqual(calls, fixture.remoteCalls)
      }
    }
  }
}
