import Foundation
import XCTest
@testable import Typebar

final class ProfileRelationshipTests: XCTestCase {
  private func profile(_ id: UUID) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: [
      "id": id.uuidString, "displayName": "Owned relation", "joinedAt": 0, "completedResultCount": 0, "bestWPM": 0]))
  }
  private func connection(_ id: UUID, _ relation: RemoteConnectionRelation) throws -> RemoteConnection {
    .init(id: id, profile: try profile(id), relation: relation, updatedAt: Date(timeIntervalSince1970: 100))
  }
  @MainActor private func session(_ body: (AccountSession, UUID, RemoteAccountUser) async throws -> Void) async throws {
    let suite = "TypebarTests.profile-relationship.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    let user = RemoteAccountUser(id: UUID(), email: "owned@example.invalid", displayName: "Owner", totalExperience: 10)
    account.currentUser = user
    try await body(account, UUID(), user)
  }

  func testSnapshotDistinguishesDirectionsFriendsBlocksAndUnrelatedUsers() throws {
    let target = UUID(), owner = UUID(), other = UUID()
    for (relation, expected) in [(RemoteConnectionRelation.friend, ProfileRelationshipStatus.friend),
      (.incomingRequest, .incomingRequest), (.outgoingRequest, .outgoingRequest)] {
      let row = try connection(target, relation)
      XCTAssertEqual(try ProfileRelationshipSnapshot(connections: [row], blockedIDs: []).status(for: target, ownerID: owner), expected)
      XCTAssertFalse(expected.canSend)
      XCTAssertEqual(try ProfileRelationshipSnapshot(connections: [row], blockedIDs: [target]).status(for: target, ownerID: owner), .blocked)
    }
    XCTAssertEqual(try ProfileRelationshipSnapshot(connections: [connection(other, .friend)], blockedIDs: [other]).status(for: target, ownerID: owner), .notConnected)
    XCTAssertTrue(ProfileRelationshipStatus.notConnected.canSend)
    for value in [ProfileRelationshipStatus.unavailable, .loading, .failed("unknown"), .blocked] { XCTAssertFalse(value.canSend) }
    let row = try connection(target, .friend)
    XCTAssertThrowsError(try ProfileRelationshipSnapshot(connections: [row, row], blockedIDs: []).status(for: target, ownerID: owner))
    XCTAssertThrowsError(try ProfileRelationshipSnapshot(connections: [connection(owner, .friend)], blockedIDs: []).status(for: target, ownerID: owner))
    let mismatched = RemoteConnection(id: UUID(), profile: try profile(target), relation: .friend, updatedAt: .now)
    XCTAssertThrowsError(try ProfileRelationshipSnapshot(connections: [mismatched], blockedIDs: []).status(for: target, ownerID: owner))
  }

  @MainActor func testAnonymousReadonlyOwnerAndOverviewNeverInvokeCredentialedProviders() async throws {
    try await session { account, target, user in
      let identities = [
        ProfileRelationshipIdentity(profileID: target, account: account, allowsAccountActions: false, retryRevision: UUID()),
        .init(profileID: target, account: account, isAccountOverview: true, retryRevision: UUID()),
        .init(profileID: user.id, account: account, retryRevision: UUID())]
      account.currentUser = nil
      let anonymous = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      for identity in identities + [anonymous] {
        let state = ProfileRelationshipState(); var calls = 0
        await state.load(identity: identity, account: account) { calls += 1; return .init(connections: [], blockedIDs: []) }
        await state.send(identity: identity, account: account) { calls += 1; return try self.connection(target, .outgoingRequest) }
        XCTAssertEqual(calls, 0); XCTAssertEqual(state.status, .unavailable)
      }
      account.currentUser = user
      let readOnly = identities[0], state = ProfileRelationshipState(); var calls = 0
      await state.load(identity: readOnly, account: account) { calls += 1; return .init(connections: [], blockedIDs: []) }
      XCTAssertEqual(calls, 0, "Authenticated anonymous sharing must still never read current credentials")
    }
  }

  @MainActor func testReaderKeepsPrivateRelationshipsOutOfAccountCachesAndRejectsSessionABA() async throws {
    try await session { account, target, user in
      let identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      let row = try self.connection(target, .friend), revision = account.accountTagRevision
      let read = try await account.loadProfileRelationship(identity: identity) { .init(connections: [row], blockedIDs: []) }
      XCTAssertEqual(read, .friend)
      XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertNil(account.lastAccountResult)
      XCTAssertNil(account.accountTagHistoryCache); XCTAssertEqual(account.accountTagRevision, revision)
      XCTAssertNil(account.statusMessage); XCTAssertFalse(account.isWorking); XCTAssertEqual(account.currentUser, user)
      for changeServer in [false, true] {
        let request = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID()), endpoint = account.endpoint
        do {
          _ = try await account.loadProfileRelationship(identity: request) {
            if changeServer { _ = account.updateEndpoint("https://other-owned.invalid"); _ = account.updateEndpoint(endpoint) }
            else { account.currentUser = nil }
            account.currentUser = user
            return .init(connections: [row], blockedIDs: [])
          }
          XCTFail("Account/server ABA must retire private reads")
        } catch let error as RemoteAccountError {
          guard case .accountScopeChanged = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(request.isCurrent(account))
      }
      let fresh = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      account.currentUser = user
      XCTAssertTrue(fresh.isCurrent(account), "Identical user refresh is not logout/login")
    }
  }

  @MainActor func testReadFailureIsUnknownAndRequiresExplicitRetry() async throws {
    try await session { account, target, _ in
      let state = ProfileRelationshipState(), identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      await state.load(identity: identity, account: account) { throw URLError(.notConnectedToInternet) }
      guard case .failed = state.status else { return XCTFail("Failure must not imply no connection") }
      var sends = 0
      await state.send(identity: identity, account: account) { sends += 1; return try self.connection(target, .outgoingRequest) }
      XCTAssertEqual(sends, 0)
      await state.load(identity: identity, account: account) { .init(connections: [], blockedIDs: []) }
      XCTAssertEqual(state.status, .notConnected)
      await state.send(identity: identity, account: account) { sends += 1; return try self.connection(target, .outgoingRequest) }
      XCTAssertEqual(sends, 1); XCTAssertEqual(state.status, .outgoingRequest); XCTAssertFalse(state.isSending)
    }
  }

  @MainActor func testOlderReadSuccessAndErrorCannotReplaceNewReadEvenWithSameIdentity() async throws {
    try await session { account, target, _ in
      for failOld in [false, true] {
        let state = ProfileRelationshipState(), identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
        var pending: CheckedContinuation<ProfileRelationshipSnapshot, Error>?
        let (started, signal) = AsyncStream<Void>.makeStream()
        let old = Task { @MainActor in await state.load(identity: identity, account: account) {
          try await withCheckedThrowingContinuation { pending = $0; signal.yield(); signal.finish() }
        } }
        for await _ in started { break }
        await state.load(identity: identity, account: account) { .init(connections: [try self.connection(target, .friend)], blockedIDs: []) }
        if failOld { pending?.resume(throwing: URLError(.timedOut)) }
        else { pending?.resume(returning: .init(connections: [], blockedIDs: [])) }
        await old.value
        XCTAssertEqual(state.status, .friend)
      }
    }
  }

  @MainActor func testDoubleSendIsSuppressedAndUncertainResponseCannotBeBlindlyRetried() async throws {
    try await session { account, target, _ in
      let state = ProfileRelationshipState(), identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      await state.load(identity: identity, account: account) { .init(connections: [], blockedIDs: []) }
      var pending: CheckedContinuation<RemoteConnection, Error>?, calls = 0
      let (started, signal) = AsyncStream<Void>.makeStream()
      let first = Task { @MainActor in await state.send(identity: identity, account: account) {
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0; signal.yield(); signal.finish() }
      } }
      for await _ in started { break }
      XCTAssertTrue(state.isSending)
      await state.send(identity: identity, account: account) { calls += 1; return try self.connection(target, .outgoingRequest) }
      pending?.resume(throwing: URLError(.timedOut)); await first.value
      XCTAssertEqual(calls, 1); XCTAssertFalse(state.isSending)
      guard case .failed(let message) = state.status else { return XCTFail("Lost response is uncertain, not unsent") }
      XCTAssertTrue(message.contains("可能已收到"))
      await state.send(identity: identity, account: account) { calls += 1; return try self.connection(target, .outgoingRequest) }
      XCTAssertEqual(calls, 1)
      await state.load(identity: identity, account: account) { .init(connections: [try self.connection(target, .outgoingRequest)], blockedIDs: []) }
      XCTAssertEqual(state.status, .outgoingRequest)
    }
  }

  @MainActor func testSendResponseMustMatchTargetDirectionAndStillCurrentSession() async throws {
    try await session { account, target, user in
      let identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      for row in [try self.connection(UUID(), .outgoingRequest), try self.connection(target, .incomingRequest), try self.connection(target, .friend)] {
        do { _ = try await account.loadProfileConnectionSend(identity: identity) { row }; XCTFail("Wrong response must reject") }
        catch let error as RemoteAccountError { guard case .unexpectedResponse = error else { return XCTFail("\(error)") } }
      }
      do {
        _ = try await account.loadProfileConnectionSend(identity: identity) {
          account.currentUser = nil; account.currentUser = user
          return try self.connection(target, .outgoingRequest)
        }
        XCTFail("Late mutation cannot confirm into a reauthenticated session")
      } catch let error as RemoteAccountError { guard case .accountScopeChanged = error else { return XCTFail("\(error)") } }
      var calls = 0
      do {
        _ = try await account.loadProfileConnectionSend(identity: identity) { calls += 1; return try self.connection(target, .outgoingRequest) }
        XCTFail("Stale scope must reject before credentialed provider")
      } catch { XCTAssertEqual(calls, 0) }
    }
  }

  @MainActor func testLateSendCannotOverwriteRefreshedOrChangedAccountRelationship() async throws {
    try await session { account, target, user in
      for changeAccount in [false, true] {
        let state = ProfileRelationshipState(), identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
        await state.load(identity: identity, account: account) { .init(connections: [], blockedIDs: []) }
        var pending: CheckedContinuation<RemoteConnection, Error>?
        let (started, signal) = AsyncStream<Void>.makeStream()
        let old = Task { @MainActor in await state.send(identity: identity, account: account) {
          try await withCheckedThrowingContinuation { pending = $0; signal.yield(); signal.finish() }
        } }
        for await _ in started { break }
        if changeAccount { account.currentUser = nil; account.currentUser = user }
        let fresh = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
        await state.load(identity: fresh, account: account) { .init(connections: [try self.connection(target, .friend)], blockedIDs: []) }
        pending?.resume(returning: try self.connection(target, .outgoingRequest)); await old.value
        XCTAssertEqual(state.displayedStatus(identity: fresh, account: account), .friend)
        XCTAssertFalse(state.isSending)
        XCTAssertEqual(state.displayedStatus(identity: identity, account: account), .unavailable)
      }
    }
  }

  @MainActor func testCancellationDoesNotInventRelationshipOrUnsentMutation() async throws {
    try await session { account, target, _ in
      let state = ProfileRelationshipState(), identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      var calls = 0
      await Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await state.load(identity: identity, account: account) { calls += 1; return .init(connections: [], blockedIDs: []) }
      }.value
      XCTAssertEqual(calls, 0); XCTAssertEqual(state.status, .unavailable)
      await Task { @MainActor in await state.load(identity: identity, account: account) {
        withUnsafeCurrentTask { $0?.cancel() }; return .init(connections: [], blockedIDs: [])
      } }.value
      XCTAssertEqual(state.status, .loading, "Cancelled read must not publish a no-relationship success")
    }
    try await session { account, target, _ in
      let state = ProfileRelationshipState(), identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      await state.load(identity: identity, account: account) { .init(connections: [], blockedIDs: []) }
      await Task { @MainActor in await state.send(identity: identity, account: account) {
        withUnsafeCurrentTask { $0?.cancel() }; return try self.connection(target, .outgoingRequest)
      } }.value
      guard case .failed = state.status else { return XCTFail("Cancellation after submission is uncertain") }
      XCTAssertFalse(state.status.canSend); XCTAssertFalse(state.isSending)
    }
  }

  @MainActor func testSameAppMutationRetiresOldReadAndTaskIdentityWithoutPersistingRelationships() async throws {
    try await session { account, target, user in
      let revision = UUID(), owner = AccountProfileEditIdentity(account: account)
      let request = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: revision)
      let state = ProfileRelationshipState()
      await state.load(identity: request, account: account) { .init(connections: [], blockedIDs: []) }
      account.noteProfileRelationshipsChanged(identity: owner)
      XCTAssertEqual(account.profileRelationshipRevision, 1)
      XCTAssertTrue(request.isCurrent(account)); XCTAssertFalse(request.isCurrentRead(account))
      XCTAssertEqual(state.displayedStatus(identity: request, account: account), .unavailable)
      let fresh = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: revision)
      XCTAssertNotEqual(request, fresh)
      var calls = 0
      await state.send(identity: request, account: account) { calls += 1; return try self.connection(target, .outgoingRequest) }
      XCTAssertEqual(calls, 0)
      await state.load(identity: fresh, account: account) {
        .init(connections: [try self.connection(target, .friend)], blockedIDs: [])
      }
      XCTAssertEqual(state.status, .friend)
      account.currentUser = nil; account.currentUser = user
      account.noteProfileRelationshipsChanged(identity: owner)
      XCTAssertEqual(account.profileRelationshipRevision, 1, "Late old-session success cannot invalidate a new session")
      XCTAssertNil(account.statusMessage); XCTAssertFalse(account.isWorking)
    }
  }

  func testAllSuccessfulRelationshipMutationsNotifyScopedViewInvalidation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/RemoteAccount.swift"), encoding: .utf8)
    for name in ["sendProfileConnection", "sendConnection", "acceptConnection", "removeConnection", "blockUser", "unblockUser"] {
      let start = try XCTUnwrap(source.range(of: "    func \(name)("))
      let remainder = source[start.upperBound...]
      let end = remainder.range(of: "\n    func ")?.lowerBound ?? remainder.endIndex
      XCTAssertTrue(remainder[..<end].contains("noteProfileRelationshipsChanged(identity: owner)"), name)
    }
  }

  @MainActor func testMutationDuringReadRejectsStaleSnapshotButOwnSuccessfulSendCanInvalidateItsView() async throws {
    try await session { account, target, _ in
      let owner = AccountProfileEditIdentity(account: account)
      let read = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      do {
        _ = try await account.loadProfileRelationship(identity: read) {
          account.noteProfileRelationshipsChanged(identity: owner)
          return .init(connections: [], blockedIDs: [])
        }
        XCTFail("Earlier read cannot claim no relationship after a same-app mutation")
      } catch let error as RemoteAccountError { guard case .accountScopeChanged = error else { return XCTFail("\(error)") } }
      var calls = 0
      do {
        _ = try await account.loadProfileConnectionSend(identity: read) { calls += 1; return try self.connection(target, .outgoingRequest) }
        XCTFail("Stale relationship revision must reject before dispatch")
      } catch { XCTAssertEqual(calls, 0) }
      let send = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
      let response = try await account.loadProfileConnectionSend(identity: send) {
        account.noteProfileRelationshipsChanged(identity: owner)
        return try self.connection(target, .outgoingRequest)
      }
      XCTAssertEqual(response.relation, .outgoingRequest)
      XCTAssertTrue(send.isCurrent(account)); XCTAssertFalse(send.isCurrentRead(account))
    }
  }

  func testProfileUsesScopedRelationshipInsteadOfUnconditionalDuplicateRequest() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let profile = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/CloudSyncView.swift"), encoding: .utf8)
    let api = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/RemoteAccount.swift"), encoding: .utf8)
    XCTAssertTrue(profile.contains("ProfileRelationshipView("))
    XCTAssertFalse(profile.contains("Button(\"发送好友请求\") { sendRequest() }"))
    XCTAssertTrue(api.contains("fetchProfileRelationship(identity:"))
    XCTAssertTrue(api.contains("sendProfileConnection(identity:"))
  }

  @MainActor func testNativeSendAvailabilityAndFriendFlagMatchCompletePinnedFunctions() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-profile-relationship.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable {
      let authenticated: Bool; let isSelf: Bool; let relation: String; let showAdd: Bool; let isFriend: Bool
    }
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 20)
    for fixture in fixtures {
      try await session { account, other, user in
        let target = fixture.isSelf ? user.id : other
        if !fixture.authenticated { account.currentUser = nil }
        let identity = ProfileRelationshipIdentity(profileID: target, account: account, retryRevision: UUID())
        let value: ProfileRelationshipStatus
        if !identity.isCurrent(account) { value = .unavailable }
        else {
          let relation: RemoteConnectionRelation? = fixture.relation == "accepted" ? .friend : fixture.relation == "outgoing" ? .outgoingRequest : fixture.relation == "incoming" ? .incomingRequest : nil
          let rows = try relation.map { [try self.connection(target, $0)] } ?? []
          value = try await account.loadProfileRelationship(identity: identity) {
            .init(connections: rows, blockedIDs: fixture.relation == "blocked" ? [target] : [])
          }
        }
        XCTAssertEqual(value.canSend, fixture.showAdd)
        XCTAssertEqual(value == .friend, fixture.isFriend)
      }
    }
  }
}
