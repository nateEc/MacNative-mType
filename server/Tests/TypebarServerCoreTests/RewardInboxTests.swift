import Foundation
import XCTest
@testable import TypebarServerCore

final class RewardInboxTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private let password = "a secure password"
  private func account(_ store: AuthStore, _ name: String = "Inbox") async throws -> AuthSessionResponse {
    try await store.register(.init(email:"\(name.lowercased())@example.com",password:password,displayName:name),now:now)
  }
  private func mail(_ xp: Int, id: UUID = UUID(), timestamp: Int = 1_800_000_000_875) -> RewardMail {
    .init(id:id,subject:"奖励",body:"本周练习奖励",timestamp:timestamp,rewards:[.xp(xp)])
  }
  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-inbox-\(UUID())")
    try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false); return value
  }
  func testDeliveryIsUnclaimedAndReadOrDeleteCreditsExactlyOnceAcrossRestart() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4)
    let owner = try await account(store), first = mail(7), second = mail(11)
    try await store.deliverRewardMail(first,userID:owner.user.id)
    try await store.deliverRewardMail(second,userID:owner.user.id)
    let initial = try await store.authenticatedUser(for:owner.accessToken,now:now)
    XCTAssertEqual(initial.totalExperience,0)
    let changed = try await store.updateRewardInbox(.init(mailIdsToMarkRead:[first.id,first.id,second.id],mailIdsToDelete:[second.id,second.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(changed.user.totalExperience,18)
    XCTAssertEqual(changed.inbox.map(\.id),[first.id]); XCTAssertTrue(changed.inbox[0].read)
    XCTAssertTrue(changed.inbox[0].rewards.isEmpty)
    let restarted = try AuthStore(fileURL:file,bcryptCost:4)
    let repeated = try await restarted.updateRewardInbox(.init(mailIdsToMarkRead:[first.id],mailIdsToDelete:[second.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(repeated.user.totalExperience,18)
    let redelivered = try await restarted.deliverRewardMail(second,userID:owner.user.id)
    XCTAssertFalse(redelivered,"Our delivery identity survives mailbox deletion")
    let board = try await restarted.experienceLeaderboard(now:now)
    XCTAssertTrue(board.entries.isEmpty,"Claim XP is not weekly typing XP")
  }
  func testCapacityDiscardIsNotClaimAndDeliveryRemainsIdempotent() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rewardInboxConfiguration:.init(enabled:true,maxMail:1))
    let owner = try await account(store), old = mail(100), new = mail(3)
    try await store.deliverRewardMail(old,userID:owner.user.id); try await store.deliverRewardMail(new,userID:owner.user.id)
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:now)
    XCTAssertEqual(inbox.inbox.map(\.id),[new.id])
    let absent = try await store.updateRewardInbox(.init(mailIdsToDelete:[old.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(absent.user.totalExperience,0)
    let redelivered = try await store.deliverRewardMail(old,userID:owner.user.id); XCTAssertFalse(redelivered)
    let claimed = try await store.updateRewardInbox(.init(mailIdsToDelete:[new.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(claimed.user.totalExperience,3)
  }
  func testDisabledMailboxHidesClaimButDoesNotEraseCreditOrStoredMail() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4)
    let owner = try await account(store), value = mail(0)
    try await store.deliverRewardMail(value,userID:owner.user.id)
    let disabled = try AuthStore(fileURL:file,bcryptCost:4,rewardInboxConfiguration:.init(enabled:false,maxMail:0))
    do { _ = try await disabled.updateRewardInbox(.init(mailIdsToMarkRead:[value.id]),accessToken:owner.accessToken,now:now); XCTFail("Disabled") }
    catch let error as RewardInboxError { XCTAssertEqual(error,.disabled) }
    let suppressed = try await disabled.deliverRewardMail(mail(10),userID:owner.user.id); XCTAssertFalse(suppressed)
    let enabled = try AuthStore(fileURL:file,bcryptCost:4)
    let read = try await enabled.updateRewardInbox(.init(mailIdsToMarkRead:[value.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(read.user.totalExperience,0); XCTAssertTrue(read.inbox[0].read)
    let zero = try AuthStore(fileURL:nil,bcryptCost:4,rewardInboxConfiguration:.init(enabled:true,maxMail:0))
    let zeroOwner = try await account(zero)
    try await zero.deliverRewardMail(mail(100),userID:zeroOwner.user.id)
    let empty = try await zero.rewardInbox(accessToken:zeroOwner.accessToken,now:now); XCTAssertTrue(empty.inbox.isEmpty)
  }
  func testAnotherAccountCannotClaimOrDeleteOwnersMail() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4), owner = try await account(store), other = try await account(store,"Other")
    let value = mail(99); try await store.deliverRewardMail(value,userID:owner.user.id)
    let response = try await store.updateRewardInbox(.init(mailIdsToDelete:[value.id]),accessToken:other.accessToken,now:now)
    XCTAssertEqual(response.user.totalExperience,0)
    let unchanged = try await store.rewardInbox(accessToken:owner.accessToken,now:now)
    XCTAssertEqual(unchanged.inbox,[value])
  }
  func testBadgeClaimPersistsFirstIdentityAndCanBeSelectedAfterDeletingMail() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4), owner = try await account(store)
    let first = PublicProfileBadge(id:"fixture-badge",title:"自己的徽章",systemImage:"star")
    let later = PublicProfileBadge(id:"fixture-badge",title:"重复徽章",systemImage:"circle")
    let value = RewardMail(subject:"徽章",body:"",timestamp:0,rewards:[.badge(first),.badge(later)])
    try await store.deliverRewardMail(value,userID:owner.user.id)
    let claimed = try await store.updateRewardInbox(.init(mailIdsToDelete:[value.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(claimed.user.availableBadges,[first])
    let selected = try await store.updateProfile(.init(selectedBadgeID:first.id),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(selected.selectedBadgeID,first.id)
  }
  func testFailedSaveRollsBackReadRewardsAndCreditThenRetryClaimsOnce() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), backup = dir.appendingPathComponent("backup.json")
    let store = try AuthStore(fileURL:file,bcryptCost:4), owner = try await account(store), value = mail(13)
    try await store.deliverRewardMail(value,userID:owner.user.id)
    try FileManager.default.moveItem(at:file,to:backup); try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
    do { _ = try await store.updateRewardInbox(.init(mailIdsToMarkRead:[value.id]),accessToken:owner.accessToken,now:now); XCTFail("Save must fail") }
    catch { }
    let unchanged = try await store.rewardInbox(accessToken:owner.accessToken,now:now); XCTAssertEqual(unchanged.inbox,[value])
    let user = try await store.authenticatedUser(for:owner.accessToken,now:now); XCTAssertEqual(user.totalExperience,0)
    try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
    let claimed = try await store.updateRewardInbox(.init(mailIdsToMarkRead:[value.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(claimed.user.totalExperience,13)
    let reload = try AuthStore(fileURL:file,bcryptCost:4)
    let twice = try await reload.updateRewardInbox(.init(mailIdsToMarkRead:[value.id]),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(twice.user.totalExperience,13)
  }
  func testOldMissingStateDoesNotBackfillAndExplicitCorruptionKeepsBytes() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4)
    _ = try await account(store)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    object.removeValue(forKey:"rewardInbox")
    object.removeValue(forKey:"rewardInboxManaged")
    let old = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try old.write(to:file,options:.atomic)
    _ = try AuthStore(fileURL:file,bcryptCost:4); XCTAssertEqual(try Data(contentsOf:file),old)
    for invalid: Any in [NSNull(),["version":2,"deliveries":[],"mails":[],"claims":[],"badges":[]]] {
      object["rewardInbox"] = invalid
      let bad = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try bad.write(to:file,options:.atomic)
      XCTAssertThrowsError(try AuthStore(fileURL:file,bcryptCost:4)); XCTAssertEqual(try Data(contentsOf:file),bad)
    }
  }
  func testStrictRequestAndRewardNumericBoundaries() throws {
    for text in [#"{"mailIdsToDelete":[]}"#,#"{"mailIdsToMarkRead":null}"#,#"{"unexpected":1}"#] {
      XCTAssertThrowsError(try JSONDecoder().decode(RewardInboxUpdateRequest.self,from:Data(text.utf8)))
    }
    XCTAssertThrowsError(try RewardInboxConfiguration(enabled:true,maxMail:-1).validate())
    XCTAssertThrowsError(try InboxReward.xp(Int.max).validate())
    XCTAssertThrowsError(try RewardInboxState.adding(9_007_199_254_740_991,1))
    try InboxReward.xp(-5).validate()
  }
  func testHistoryDeletionKeepsClaimCreditAndAccountResetClearsIt() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4), owner = try await account(store), value = mail(15)
    try await store.deliverRewardMail(value,userID:owner.user.id)
    _ = try await store.updateRewardInbox(.init(mailIdsToMarkRead:[value.id]),accessToken:owner.accessToken,now:now)
    _ = try await store.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    let retained = try await store.authenticatedUser(for:owner.accessToken,now:now); XCTAssertEqual(retained.totalExperience,15)
    let reset = try await store.resetAccount(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(reset.totalExperience,0)
    let inbox = try await store.rewardInbox(accessToken:owner.accessToken,now:now); XCTAssertTrue(inbox.inbox.isEmpty)
  }
  func testMissingManagedInboxCannotSilentlyLoseClaimedCredit() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4)
    let owner = try await account(store), value = mail(10)
    try await store.deliverRewardMail(value,userID:owner.user.id)
    _ = try await store.updateRewardInbox(.init(mailIdsToDelete:[value.id]),accessToken:owner.accessToken,now:now)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    object.removeValue(forKey:"rewardInbox")
    let bytes = try JSONSerialization.data(withJSONObject:object,options:.sortedKeys); try bytes.write(to:file,options:.atomic)
    XCTAssertThrowsError(try AuthStore(fileURL:file,bcryptCost:4))
    XCTAssertEqual(try Data(contentsOf:file),bytes)
  }
  func testActualPinnedGeneratedClaimFunctionAndRetries() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned source") }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-inbox-claims.mjs")
    let process = Process(), output = Pipe(), error = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = error; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostic = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostic,as:UTF8.self))
    struct Inventory: Decodable { let badges:[PublicProfileBadge] }
    struct Expected: Decodable { let inbox:[RewardMail]; let xp:Int; let inventory:Inventory }
    struct Fixture: Decodable { let read:[UUID]; let deleted:[UUID]; let existingBadges:[PublicProfileBadge]; let expected:Expected }
    struct Document: Decodable { let referenceCommit:String; let inbox:[RewardMail]; let fixtures:[Fixture] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(document.fixtures.count,108)
    let owner = UUID()
    for fixture in document.fixtures {
      var state = RewardInboxState()
      for mail in document.inbox.reversed() {
        var seed = mail; seed.read = false
        try state.insert(seed,for:owner,configuration:.typebarDefault)
      }
      for mail in document.inbox where mail.read {
        try state.update(.init(mailIdsToMarkRead:[mail.id]),for:owner,totalExperience:100,existingBadges:[],now:now)
      }
      let request = RewardInboxUpdateRequest(mailIdsToMarkRead:fixture.read.isEmpty ? nil : fixture.read,
        mailIdsToDelete:fixture.deleted.isEmpty ? nil : fixture.deleted)
      try state.update(request,for:owner,totalExperience:100,existingBadges:fixture.existingBadges,now:now)
      XCTAssertEqual(100 + state.experience(for:owner),fixture.expected.xp)
      XCTAssertEqual(state.inbox(for:owner),fixture.expected.inbox)
      XCTAssertEqual(state.inventory(for:owner),fixture.expected.inventory.badges)
      try state.validate(users:[owner])
      try state.update(request,for:owner,totalExperience:fixture.expected.xp,existingBadges:fixture.existingBadges,now:now)
      XCTAssertEqual(100 + state.experience(for:owner),fixture.expected.xp)
      XCTAssertEqual(state.inbox(for:owner),fixture.expected.inbox)
    }
  }
}
