import Foundation
import XCTest
@testable import Typebar

final class ConnectionsManagementTests: XCTestCase {
  private func profile(_ id: UUID = UUID()) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: [
      "id": id.uuidString, "displayName": "Owned manager profile", "joinedAt": 0, "completedResultCount": 0, "bestWPM": 0]))
  }
  private func row(_ id: UUID, _ relation: RemoteConnectionRelation, seconds: Double = 1) throws -> RemoteConnection {
    .init(id: id, profile: try profile(id), relation: relation, updatedAt: .init(timeIntervalSince1970: seconds))
  }
  @MainActor private func session(_ body: (AccountSession, ConnectionsOwnerIdentity, UUID) async throws -> Void) async throws {
    let suite = "TypebarTests.connections-manager.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owner", totalExperience: 0)
    try await body(account, .init(account: account), UUID())
  }
  @MainActor private func read(_ owner: ConnectionsOwnerIdentity, _ account: AccountSession) -> ConnectionsReadIdentity {
    .init(owner: owner, account: account, refresh: UUID())
  }
  private var empty: ConnectionsSnapshot { .init(connections: [], blockedProfiles: []) }

  func testSnapshotPartitionsDirectionsOrdersNewestFirstAndValidatesPrivateRows() throws {
    let owner = UUID(), incoming = UUID(), outgoing = UUID(), friend = UUID(), blocked = UUID()
    let snapshot = ConnectionsSnapshot(connections: [try row(incoming, .incomingRequest), try row(outgoing, .outgoingRequest, seconds: 3),
      try row(friend, .friend, seconds: 2), try row(blocked, .friend)], blockedProfiles: [try profile(blocked)])
    try snapshot.validate(ownerID: owner)
    XCTAssertEqual(snapshot.visibleConnections.map(\.id), [outgoing, friend, incoming])
    for (id, status) in [(incoming, ProfileRelationshipStatus.incomingRequest), (outgoing, .outgoingRequest), (friend, .friend), (blocked, .blocked)] {
      XCTAssertEqual(snapshot.status(for: id), status)
      XCTAssertFalse(snapshot.allows(.send(id), ownerID: owner))
      XCTAssertEqual(snapshot.allows(.accept(id), ownerID: owner), id == incoming)
      XCTAssertEqual(snapshot.allows(.remove(id), ownerID: owner), id != blocked)
      XCTAssertEqual(snapshot.allows(.unblock(id), ownerID: owner), id == blocked)
      XCTAssertEqual(snapshot.allows(.block(id), ownerID: owner), id != blocked)
    }
    XCTAssertTrue(snapshot.allows(.send(UUID()), ownerID: owner))
    for action in [ConnectionsMutation.send(owner), .accept(owner), .remove(owner), .block(owner), .unblock(owner)] {
      XCTAssertFalse(snapshot.allows(action, ownerID: owner))
    }
    XCTAssertThrowsError(try ConnectionsSnapshot(connections: [row(owner, .friend)], blockedProfiles: []).validate(ownerID: owner))
    XCTAssertThrowsError(try ConnectionsSnapshot(connections: [], blockedProfiles: [profile(owner)]).validate(ownerID: owner))
    XCTAssertThrowsError(try ConnectionsSnapshot(connections: [], blockedProfiles: [profile(blocked), profile(blocked)]).validate(ownerID: owner))
    XCTAssertThrowsError(try ConnectionsSnapshot(connections: [row(friend, .friend), row(friend, .friend)], blockedProfiles: []).validate(ownerID: owner))
  }

  @MainActor func testScopeHidesPrivateRowsAndRejectsAnonymousProvidersBeforeCredentials() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(), request = self.read(owner, account), user = account.currentUser
      await state.load(request: request, account: account) { .init(connections: [try self.row(target, .friend)], blockedProfiles: []) }
      XCTAssertNotNil(state.displayedSnapshot(request: request, account: account))
      account.currentUser = user
      XCTAssertTrue(owner.isCurrent(account), "Ordinary identical refresh preserves this page")
      account.currentUser = nil
      XCTAssertNil(state.displayedSnapshot(request: request, account: account))
      let anonymous = ConnectionsOwnerIdentity(account: account), invalid = self.read(anonymous, account); var calls = 0
      await state.load(request: invalid, account: account) { calls += 1; return self.empty }
      await state.search(query: "owned", owner: anonymous, account: account) { _ in calls += 1; return [] }
      _ = await state.perform(.block(target), request: invalid, account: account) { calls += 1 }
      XCTAssertEqual(calls, 0)
      account.currentUser = user
      XCTAssertFalse(owner.isCurrent(account), "Logout/login ABA must not restore old page")
      XCTAssertNil(state.displayedSnapshot(request: request, account: account))
    }
  }

  @MainActor func testOwnerAndReadGuardsRejectServerABAAndMidReadRelationshipChanges() async throws {
    try await session { account, owner, _ in
      let request = self.read(owner, account), endpoint = account.endpoint, user = account.currentUser
      do {
        _ = try await account.loadConnectionsSnapshot(identity: request) {
          _ = account.updateEndpoint("https://owned-other.invalid"); _ = account.updateEndpoint(endpoint)
          return self.empty
        }
        XCTFail("Server ABA must reject")
      } catch { XCTAssertFalse(owner.isCurrent(account)) }
      account.currentUser = user
      let current = ConnectionsOwnerIdentity(account: account), revision = self.read(current, account)
      do {
        _ = try await account.loadConnectionsSnapshot(identity: revision) {
          account.noteProfileRelationshipsChanged(identity: current.owner); return self.empty
        }
        XCTFail("Mutation during read must retire snapshot")
      } catch { XCTAssertFalse(revision.isCurrent(account)); XCTAssertTrue(current.isCurrent(account)) }
      var calls = 0
      do { try await account.loadConnectionsMutation(identity: revision) { calls += 1 }; XCTFail("Stale write must not dispatch") }
      catch { XCTAssertEqual(calls, 0) }
      let latest = self.read(current, account)
      try await account.loadConnectionsMutation(identity: latest) { account.noteProfileRelationshipsChanged(identity: current.owner) }
      XCTAssertFalse(latest.isCurrent(account), "Own successful write may advance the relation revision")
    }
  }

  @MainActor func testOlderReadSuccessOrFailureCannotOverwriteNewSnapshotWithSameIdentity() async throws {
    try await session { account, owner, target in
      for fails in [false, true] {
        let state = ConnectionsManagementState(), request = self.read(owner, account)
        var pending: CheckedContinuation<ConnectionsSnapshot, Error>?
        let (started, signal) = AsyncStream<Void>.makeStream()
        let old = Task { @MainActor in await state.load(request: request, account: account) {
          try await withCheckedThrowingContinuation { pending = $0; signal.yield(); signal.finish() }
        } }
        for await _ in started { break }
        await state.load(request: request, account: account) { .init(connections: [try self.row(target, .friend)], blockedProfiles: []) }
        if fails { pending?.resume(throwing: URLError(.timedOut)) } else { pending?.resume(returning: self.empty) }
        await old.value
        XCTAssertEqual(state.snapshot?.status(for: target), .friend); XCTAssertFalse(state.isLoading)
      }
    }
  }

  @MainActor func testFailedOrMalformedReadIsUnknownUntilSuccessfulRefresh() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(), request = self.read(owner, account)
      for invalid in [false, true] {
        await state.load(request: request, account: account) {
          if !invalid { throw URLError(.notConnectedToInternet) }
          return .init(connections: [try self.row(target, .friend), try self.row(target, .friend)], blockedProfiles: [])
        }
        XCTAssertNil(state.snapshot); XCTAssertTrue(state.message?.contains("未知") == true)
        var calls = 0
        _ = await state.perform(.send(target), request: request, account: account) { calls += 1 }
        XCTAssertEqual(calls, 0)
      }
      await state.load(request: request, account: account) { self.empty }
      XCTAssertTrue(state.canPerform(.send(target), request: request, account: account))
      XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertNil(account.statusMessage); XCTAssertFalse(account.isWorking)
    }
  }

  @MainActor func testEveryMutationRequiresKnownAppropriateRelationAndRefreshesAfterConfirmation() async throws {
    try await session { account, owner, target in
      for action in [ConnectionsMutation.send(target), .accept(target), .remove(target), .block(target), .unblock(target)] {
        let state = ConnectionsManagementState(), request = self.read(owner, account)
        let snapshot: ConnectionsSnapshot
        switch action {
        case .accept: snapshot = .init(connections: [try self.row(target, .incomingRequest)], blockedProfiles: [])
        case .remove: snapshot = .init(connections: [try self.row(target, .friend)], blockedProfiles: [])
        case .unblock: snapshot = .init(connections: [], blockedProfiles: [try self.profile(target)])
        default: snapshot = self.empty
        }
        await state.load(request: request, account: account) { snapshot }
        XCTAssertTrue(state.canPerform(action, request: request, account: account))
        var calls = 0
        let confirmed = await state.perform(action, request: request, account: account) {
          calls += 1; account.noteProfileRelationshipsChanged(identity: owner.owner)
        }
        XCTAssertTrue(confirmed); XCTAssertEqual(calls, 1); XCTAssertFalse(state.isMutating)
        XCTAssertNil(state.displayedSnapshot(request: request, account: account))
        XCTAssertFalse(state.canPerform(action, request: request, account: account))
        let fresh = self.read(owner, account)
        await state.load(request: fresh, account: account) { self.empty }
        XCTAssertNotNil(state.displayedSnapshot(request: fresh, account: account))
      }
    }
  }

  @MainActor func testDoubleAndConflictingOperationsDispatchOnlyOnceAndRequireRefreshAfterUncertainFailure() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(), request = self.read(owner, account)
      await state.load(request: request, account: account) { self.empty }
      var pending: CheckedContinuation<Void, Error>?, calls = 0
      let (started, signal) = AsyncStream<Void>.makeStream()
      let old = Task { @MainActor in await state.perform(.send(target), request: request, account: account) {
        calls += 1
        try await withCheckedThrowingContinuation { pending = $0; signal.yield(); signal.finish() }
      } }
      for await _ in started { break }
      XCTAssertTrue(state.isMutating)
      for action in [ConnectionsMutation.send(target), .block(target), .send(UUID())] {
        let confirmed = await state.perform(action, request: request, account: account) { calls += 1 }
        XCTAssertFalse(confirmed)
      }
      pending?.resume(throwing: URLError(.timedOut)); let confirmed = await old.value
      XCTAssertFalse(confirmed); XCTAssertEqual(calls, 1); XCTAssertNil(state.snapshot)
      XCTAssertTrue(state.message?.contains("可能已收到") == true); XCTAssertFalse(state.isMutating)
      _ = await state.perform(.send(target), request: request, account: account) { calls += 1 }
      XCTAssertEqual(calls, 1)
      await state.load(request: request, account: account) { .init(connections: [try self.row(target, .outgoingRequest)], blockedProfiles: []) }
      XCTAssertFalse(state.canPerform(.send(target), request: request, account: account))
    }
  }

  @MainActor func testReadBegunBeforeUncertainWriteOutcomeCannotUnlockWritesAfterFailure() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(), request = self.read(owner, account)
      await state.load(request: request, account: account) { self.empty }
      var write: CheckedContinuation<Void, Error>?, read: CheckedContinuation<ConnectionsSnapshot, Error>?
      let (writeStarted, writeSignal) = AsyncStream<Void>.makeStream(), (readStarted, readSignal) = AsyncStream<Void>.makeStream()
      let mutation = Task { @MainActor in await state.perform(.send(target), request: request, account: account) {
        try await withCheckedThrowingContinuation { write = $0; writeSignal.yield(); writeSignal.finish() }
      } }
      for await _ in writeStarted { break }
      let load = Task { @MainActor in await state.load(request: request, account: account) {
        try await withCheckedThrowingContinuation { read = $0; readSignal.yield(); readSignal.finish() }
      } }
      for await _ in readStarted { break }
      write?.resume(throwing: URLError(.networkConnectionLost)); _ = await mutation.value
      read?.resume(returning: self.empty); await load.value
      XCTAssertNil(state.snapshot); XCTAssertFalse(state.isLoading)
      XCTAssertFalse(state.canPerform(.send(target), request: request, account: account))
      XCTAssertTrue(state.message?.contains("未确认") == true)
    }
  }

  @MainActor func testLateMutationDoesNotTouchNewSessionDataOrTriggerNewOwnerRefresh() async throws {
    try await session { account, owner, target in
      for fails in [false, true] {
        let current = ConnectionsOwnerIdentity(account: account), request = self.read(current, account), state = ConnectionsManagementState()
        await state.load(request: request, account: account) { self.empty }
        let user = account.currentUser
        let confirmed = await state.perform(.block(target), request: request, account: account) {
          account.currentUser = nil; account.currentUser = user
          account.noteProfileRelationshipsChanged(identity: current.owner)
          if fails { throw URLError(.timedOut) }
        }
        XCTAssertFalse(confirmed); XCTAssertFalse(state.isMutating)
        XCTAssertFalse(current.isCurrent(account)); XCTAssertEqual(account.profileRelationshipRevision, 0)
        XCTAssertNil(state.displayedSnapshot(request: request, account: account))
        XCTAssertNil(account.statusMessage)
      }
      XCTAssertFalse(owner.isCurrent(account))
    }
  }

  @MainActor func testCancellationBeforeProvidersAndAfterDispatchNeverClaimsRollback() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(), request = self.read(owner, account); var calls = 0
      await Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await state.load(request: request, account: account) { calls += 1; return self.empty }
        await state.search(query: "owned", owner: owner, account: account) { _ in calls += 1; return [] }
        _ = await state.perform(.send(target), request: request, account: account) { calls += 1 }
      }.value
      XCTAssertEqual(calls, 0)
      await state.load(request: request, account: account) { self.empty }
      let confirmed = await Task { @MainActor in await state.perform(.send(target), request: request, account: account) {
        calls += 1; withUnsafeCurrentTask { $0?.cancel() }
      } }.value
      XCTAssertFalse(confirmed); XCTAssertEqual(calls, 1); XCTAssertNil(state.snapshot)
      XCTAssertTrue(state.message?.contains("可能已收到") == true)
      await Task { @MainActor in await state.load(request: request, account: account) {
        withUnsafeCurrentTask { $0?.cancel() }; return self.empty
      } }.value
      XCTAssertNil(state.snapshot); XCTAssertFalse(state.isLoading)
    }
  }

  @MainActor func testSearchCapturesNormalizedQueryAndOldResponseCannotSurviveInputEditOrNewSearch() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(); var calls = 0
      for invalid in ["a", "\n", String(repeating: "x", count: 41), "has\nnewline"] {
        await state.search(query: invalid, owner: owner, account: account) { _ in calls += 1; return [] }
      }
      XCTAssertEqual(calls, 0)
      var pending: CheckedContinuation<[RemotePublicProfile], Error>?
      let (started, signal) = AsyncStream<Void>.makeStream()
      let old = Task { @MainActor in await state.search(query: "  old  ", owner: owner, account: account) { query in
        XCTAssertEqual(query, "old"); calls += 1
        return try await withCheckedThrowingContinuation { pending = $0; signal.yield(); signal.finish() }
      } }
      for await _ in started { break }
      state.clearSearch()
      await state.search(query: "new", owner: owner, account: account) { _ in [try self.profile(target), try self.profile(owner.owner.scope!.userID)] }
      pending?.resume(returning: [try self.profile()]); await old.value
      XCTAssertEqual(state.displayedSearch(owner: owner, account: account).map(\.id), [target]); XCTAssertFalse(state.isSearching)
      state.clearSearch(); XCTAssertTrue(state.searchResults.isEmpty)
    }
  }

  @MainActor func testSearchDuplicatesErrorsAndSessionABADoNotPublishResults() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState()
      await state.search(query: "owned", owner: owner, account: account) { _ in [try self.profile(target), try self.profile(target)] }
      XCTAssertTrue(state.searchResults.isEmpty); XCTAssertTrue(state.searchMessage?.contains("搜索失败") == true)
      await state.search(query: "owned", owner: owner, account: account) { _ in throw URLError(.timedOut) }
      XCTAssertTrue(state.searchResults.isEmpty); XCTAssertFalse(state.isSearching)
      let user = account.currentUser
      await state.search(query: "owned", owner: owner, account: account) { _ in
        account.currentUser = nil; account.currentUser = user; return [try self.profile(target)]
      }
      XCTAssertTrue(state.displayedSearch(owner: owner, account: account).isEmpty)
      XCTAssertFalse(state.isSearching)
    }
  }

  @MainActor func testSearchFeedbackPreservesUnknownWriteWarningAndClearsWithInputOrScope() async throws {
    try await session { account, owner, target in
      let state = ConnectionsManagementState(), request = self.read(owner, account)
      await state.load(request: request, account: account) { self.empty }
      _ = await state.perform(.send(target), request: request, account: account) { throw URLError(.timedOut) }
      let warning = state.message
      await state.search(query: "owned", owner: owner, account: account) { _ in [] }
      XCTAssertEqual(state.displayedSearchMessage(owner: owner, account: account), "没有匹配的公开展示名。")
      XCTAssertEqual(state.message, warning); XCTAssertNil(state.snapshot)
      await state.search(query: "owned", owner: owner, account: account) { _ in [try self.profile(target)] }
      XCTAssertEqual(state.displayedSearchMessage(owner: owner, account: account), "找到 1 位用户。")
      await state.search(query: "owned", owner: owner, account: account) { _ in throw URLError(.timedOut) }
      XCTAssertTrue(state.searchMessage?.contains("搜索失败") == true); XCTAssertEqual(state.message, warning)
      state.clearSearch(); XCTAssertNil(state.searchMessage)
      account.currentUser = nil; XCTAssertNil(state.displayedSearchMessage(owner: owner, account: account))
    }
  }

  func testProductionFriendsPageUsesScopedStateAndOwnedTasks() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/ConnectionsView.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("ConnectionsManagementState()"))
    XCTAssertTrue(source.contains(".task(id: request)"))
    XCTAssertTrue(source.contains(".onDisappear { cancelTasks() }"))
    XCTAssertFalse(source.contains("connections = try await account.connections()"))
  }

  @MainActor func testActualNetworkEntrypointsRejectStaleIdentityWithoutKeychainOrHTTP() async throws {
    try await session { account, owner, target in
      let request = self.read(owner, account)
      account.currentUser = nil
      let operations: [() async throws -> Void] = [
        { _ = try await account.sendConnection(to: target, identity: request) },
        { _ = try await account.acceptConnection(from: target, identity: request) },
        { try await account.removeConnection(with: target, identity: request) },
        { try await account.blockUser(target, identity: request) },
        { try await account.unblockUser(target, identity: request) },
        { _ = try await account.searchConnectionsProfiles(query: "owned", identity: owner) },
        { _ = try await account.fetchConnectionsSnapshot(identity: request) },
        { try await account.performConnectionsMutation(.send(target), identity: request) }
      ]
      for operation in operations {
        do { try await operation(); XCTFail("Retired identity must reject before credentials or transport") }
        catch let error as RemoteAccountError {
          guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
        }
      }
      XCTAssertEqual(account.profileRelationshipRevision, 0); XCTAssertNil(account.statusMessage)
    }
  }

  @MainActor func testActualWritesRejectOutdatedRelationshipRevisionBeforeCredentials() async throws {
    try await session { account, owner, target in
      let request = self.read(owner, account)
      account.noteProfileRelationshipsChanged(identity: owner.owner)
      XCTAssertTrue(owner.isCurrent(account)); XCTAssertFalse(request.isCurrent(account))
      let operations: [() async throws -> Void] = [
        { _ = try await account.sendConnection(to: target, identity: request) },
        { _ = try await account.acceptConnection(from: target, identity: request) },
        { try await account.removeConnection(with: target, identity: request) },
        { try await account.blockUser(target, identity: request) },
        { try await account.unblockUser(target, identity: request) },
        { _ = try await account.fetchConnectionsSnapshot(identity: request) },
        { try await account.performConnectionsMutation(.block(target), identity: request) }
      ]
      for operation in operations {
        do { try await operation(); XCTFail("Outdated known relationships must not dispatch") }
        catch let error as RemoteAccountError {
          guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
        }
      }
      XCTAssertEqual(account.profileRelationshipRevision, 1)
    }
  }

  @MainActor func testNativeManagerAddAvailabilityMatchesPinnedActualSourcePredicates() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned reference") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-profile-relationship.mjs")
    let process = Process(), output = Pipe(), diagnostics = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = diagnostics; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(), errors = diagnostics.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors, as: UTF8.self))
    struct Fixture: Decodable { let authenticated: Bool; let isSelf: Bool; let relation: String; let showAdd: Bool }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: bytes)
    XCTAssertEqual(fixtures.count, 20)
    for fixture in fixtures {
      try await session { account, owner, other in
        let target = fixture.isSelf ? owner.owner.scope!.userID : other
        if !fixture.authenticated { account.currentUser = nil }
        let request = self.read(owner, account), state = ConnectionsManagementState()
        await state.load(request: request, account: account) {
          let relation: RemoteConnectionRelation? = fixture.relation == "accepted" ? .friend : fixture.relation == "outgoing" ? .outgoingRequest : fixture.relation == "incoming" ? .incomingRequest : nil
          // Own identity must not be a server connection row, even in synthetic source fixtures.
          let rows = try relation.flatMap { fixture.isSelf ? nil : [try self.row(target, $0)] } ?? []
          return .init(connections: rows, blockedProfiles: fixture.relation == "blocked" && !fixture.isSelf ? [try self.profile(target)] : [])
        }
        XCTAssertEqual(state.canPerform(.send(target), request: request, account: account), fixture.showAdd)
      }
    }
  }
}
