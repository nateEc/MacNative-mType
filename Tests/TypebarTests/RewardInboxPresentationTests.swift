import Foundation
import XCTest
@testable import Typebar

final class RewardInboxPresentationTests: XCTestCase {
  func testBadgeNoticeNamesOnlyComeFromExplicitlyClaimedUnclaimedBadgeMail() throws {
    let badge: [String: Any] = ["type": "badge", "item": ["id": "owned", "title": "Owned badge", "systemImage": "star"]]
    let reward = try mail(object(rewards: [badge, ["type": "xp", "item": 25]])), xp = try mail(object())
    let read = try mail(object(read: true, rewards: []))
    XCTAssertEqual(RewardInboxPresentation.badgeNamesToClaim([reward, xp, read], request: .init(mailIdsToMarkRead: [reward.id, xp.id, read.id])), ["Owned badge"])
    XCTAssertTrue(RewardInboxPresentation.badgeNamesToClaim([reward], request: .init(mailIdsToDelete: [reward.id])).isEmpty)
    XCTAssertTrue(RewardInboxPresentation.badgeNamesToClaim([reward, xp], request: .init(mailIdsToMarkRead: [xp.id])).isEmpty)
  }
  private func object(subject: String = "奖励", read: Bool = false, rewards: [[String:Any]] = [["type":"xp","item":0]], timestamp: Int = 20) -> [String:Any] {
    ["id":UUID().uuidString,"subject":subject,"body":"独立练习奖励","timestamp":timestamp,"read":read,"rewards":rewards]
  }
  private func mail(_ object: [String:Any]) throws -> RemoteRewardMail {
    try JSONDecoder().decode(RemoteRewardMail.self,from:JSONSerialization.data(withJSONObject:object))
  }
  func testZeroAndNegativeRewardsStillRequireExplicitClaimAndNoBulkDelete() throws {
    let zero = try mail(object()), negative = try mail(object(rewards:[["type":"xp","item":-5]]))
    XCTAssertEqual(zero.statusLabel,"待领取"); XCTAssertEqual(negative.rewards.first?.label,"-5 XP")
    XCTAssertEqual(RewardInboxPresentation.claimable([zero,negative]),[zero.id,negative.id])
    XCTAssertTrue(RewardInboxPresentation.deletable([zero,negative]).isEmpty)
  }
  func testReadAndUnrewardedMailMayBeDeletedWithoutPretendingToClaim() throws {
    let read = try mail(object(read:true,rewards:[])), unread = try mail(object(rewards:[]))
    XCTAssertEqual(read.statusLabel,"已读"); XCTAssertEqual(unread.statusLabel,"未读")
    XCTAssertTrue(RewardInboxPresentation.claimable([read,unread]).isEmpty)
    XCTAssertEqual(RewardInboxPresentation.deletable([read,unread]),[read.id,unread.id])
  }
  func testDisplaySortUsesNewestThenLocaleSubjectAndStableFullTies() throws {
    let z = try mail(object(subject:"Z")), a = try mail(object(subject:"A")), another = try mail(object(subject:"A"))
    let recent = try mail(object(subject:"Z",timestamp:21)), old = try mail(object(subject:"A",timestamp:19))
    XCTAssertEqual(RewardInboxPresentation.ordered([z,a,another,old,recent],locale:Locale(identifier:"en-US")).map(\.id),[recent.id,a.id,another.id,z.id,old.id])
    let emoji = try mail(object(subject:"😀")), privateUse = try mail(object(subject:"\u{E000}"))
    XCTAssertEqual(RewardInboxPresentation.ordered([privateUse,emoji],locale:Locale(identifier:"en-US")).first?.id,emoji.id)
    let composed = try mail(object(subject:"é")), decomposed = try mail(object(subject:"e\u{301}"))
    for locale in ["en-US","de","sv","zh"] {
      XCTAssertEqual(RewardInboxPresentation.ordered([composed,decomposed],locale:Locale(identifier:locale)).map(\.id),[composed.id,decomposed.id])
    }
  }
  func testInvalidServerMailAndUnknownRewardsAreRejected() throws {
    for value in [object(read:true),object(timestamp:-1),object(rewards:[["type":"premium","item":1]]),
      object(rewards:[["type":"xp","item":9_007_199_254_740_992]]),object(rewards:[["type":"badge","item":["id":"","title":"Badge","systemImage":"star"]]])] {
      XCTAssertThrowsError(try mail(value))
    }
    var value = object(); value["timestamp"] = NSNull(); XCTAssertThrowsError(try mail(value))
  }
  func testInboxDuplicateIDsAndMalformedCapacityAreRejectedButZeroIsValid() throws {
    let value = object()
    for object: [String:Any] in [["inbox":[value,value],"maxMail":100],["inbox":[],"maxMail":-1],["inbox":[],"maxMail":NSNull()]] {
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteRewardInbox.self,from:JSONSerialization.data(withJSONObject:object)))
    }
    let empty = try JSONDecoder().decode(RemoteRewardInbox.self,from:Data(#"{"inbox":[],"maxMail":0}"#.utf8))
    XCTAssertTrue(empty.inbox.isEmpty); XCTAssertEqual(empty.maxMail,0)
  }
  func testCapabilitiesRequireExactProtocolAndExplicitAvailability() {
    for state in ["planned","disabled","unknown"] {
      XCTAssertFalse(RemoteServiceCapabilities(apiVersion:"v1",service:"typebar",capabilities:["rewardInbox":state]).supportsRewardInbox)
    }
    XCTAssertFalse(RemoteServiceCapabilities(apiVersion:"v2",service:"typebar",capabilities:["rewardInbox":"available"]).supportsRewardInbox)
    XCTAssertFalse(RemoteServiceCapabilities(apiVersion:"v1",service:"other",capabilities:["rewardInbox":"available"]).supportsRewardInbox)
    XCTAssertTrue(RemoteServiceCapabilities(apiVersion:"v1",service:"typebar",capabilities:["rewardInbox":"available"]).supportsRewardInbox)
  }
  func testLateResponseCannotCrossAccountOrServerOrSignedOutScope() {
    let user = UUID(), first = ResultPublicationScope(endpoint:"https://first.example",userID:user)
    XCTAssertTrue(RewardInboxScopePolicy.accepts(requested:first,current:first,returnedUserID:user))
    XCTAssertFalse(RewardInboxScopePolicy.accepts(requested:first,current:first,returnedUserID:UUID()))
    XCTAssertFalse(RewardInboxScopePolicy.accepts(requested:first,current:ResultPublicationScope(endpoint:"https://second.example",userID:user)))
    XCTAssertFalse(RewardInboxScopePolicy.accepts(requested:first,current:nil))
    XCTAssertFalse(RewardInboxScopePolicy.accepts(requested:nil,current:nil))
  }
  func testClaimRequestOmitsDeleteFieldRatherThanSendingEmptyArrays() throws {
    let id = UUID(), data = try JSONEncoder().encode(RemoteRewardInboxUpdate(mailIdsToMarkRead:[id]))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    XCTAssertEqual(Set(object.keys),["mailIdsToMarkRead"])
    XCTAssertEqual((object["mailIdsToMarkRead"] as? [String])?.first,id.uuidString)
  }
  func testClaimResponseDecodesMailboxAndAuthoritativeXPAndBadgeInventoryTogether() throws {
    let id = UUID(), badge: [String:Any] = ["id":"fixture-badge","title":"自己的徽章","systemImage":"star"]
    let user: [String:Any] = ["id":id.uuidString,"email":"codec@example.com","displayName":"Codec",
      "totalExperience":25,"availableBadges":[badge],"selectedBadgeID":"fixture-badge"]
    let payload: [String:Any] = ["inbox":[object(read:true,rewards:[])],"maxMail":100,"user":user]
    let decoded = try JSONDecoder().decode(RemoteRewardInboxUpdateResponse.self,from:JSONSerialization.data(withJSONObject:payload))
    XCTAssertEqual(decoded.user.id,id); XCTAssertEqual(decoded.user.totalExperience,25)
    XCTAssertEqual(decoded.user.availableBadges.first?.id,"fixture-badge")
    XCTAssertEqual(decoded.user.selectedBadgeID,"fixture-badge")
    XCTAssertTrue(decoded.mailbox.inbox[0].read); XCTAssertTrue(decoded.mailbox.inbox[0].rewards.isEmpty)
  }
  func testActualPinnedDependencyTitleOrderingAcrossFourLocales() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies source and QA comparator") }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-inbox-order.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Fixture: Decodable { let locale:String; let input:[String]; let expected:[String] }
    struct Document: Decodable { let referenceCommit:String; let dependency:String; let fixtures:[Fixture] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.dependency,"@tanstack/db@0.6.8"); XCTAssertEqual(document.fixtures.count,12)
    for fixture in document.fixtures {
      let inbox = try fixture.input.map { try mail(object(subject:$0)) }
      // Exact code-unit comparison keeps canonically equivalent spellings visible.
      let actual = RewardInboxPresentation.ordered(inbox,locale:Locale(identifier:fixture.locale)).map(\.subject)
      XCTAssertEqual(actual.map { Array($0.utf16) },fixture.expected.map { Array($0.utf16) },fixture.locale)
    }
  }
}
