import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class RewardInboxRouteTests: XCTestCase {
  func testAuthenticatedInboxIsDistinctFromRelationshipNotificationsAndAdvertised() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4)
    let owner = try await store.register(.init(email:"inbox-route@example.com",password:"a secure password",displayName:"Inbox"))
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      try await app.test(.GET,"v1/inbox",beforeRequest: { $0.headers.bearerAuthorization = .init(token:owner.accessToken) }) { response async throws in
        XCTAssertEqual(response.status,.ok)
        if response.status == .ok {
          let object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(response.body.string.utf8)) as? [String:Any])
          XCTAssertEqual((object["inbox"] as? [Any])?.count,0)
          XCTAssertEqual(object["maxMail"] as? Int,100)
        }
      }
      try await app.test(.GET,"v1/capabilities") { response async throws in
        let capabilities = try response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(capabilities.capabilities["rewardInbox"],.available)
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }

  func testInboxRoutesRequireAnAccountSession() async throws {
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:AuthStore(fileURL:nil,bcryptCost:4))
      for method in [HTTPMethod.GET,.PATCH] {
        try await app.test(method,"v1/inbox") { response async throws in
          XCTAssertEqual(response.status,.unauthorized)
        }
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
  func testDisabledInboxMatchesSourceConfigurationGate503() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rewardInboxConfiguration:.init(enabled:false,maxMail:0))
    let owner = try await store.register(.init(email:"disabled-inbox@example.com",password:"a secure password",displayName:"Disabled"))
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      for method in [HTTPMethod.GET,.PATCH] {
        try await app.test(method,"v1/inbox",beforeRequest: { request in
          request.headers.bearerAuthorization = .init(token:owner.accessToken)
          // The configuration gate must run before request body decoding.
          if method == .PATCH { request.headers.contentType = .json; request.body = .init(string:"invalid") }
        }) { response async throws in XCTAssertEqual(response.status,.serviceUnavailable) }
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
  func testHTTPClaimIsOwnerScopedOnceOnlyAndStrictlyValidated() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4)
    let owner = try await store.register(.init(email:"owner-inbox@example.com",password:"a secure password",displayName:"Owner"))
    let other = try await store.register(.init(email:"other-inbox@example.com",password:"a secure password",displayName:"Other"))
    let mail = RewardMail(subject:"HTTP 奖励",body:"自己的邮件",timestamp:0,rewards:[.xp(25)])
    try await store.deliverRewardMail(mail,userID:owner.user.id)
    let app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store,moderationKey:"fixture-moderation")
      for (token,xp) in [(other.accessToken,0),(owner.accessToken,25),(owner.accessToken,25)] {
        try await app.test(.PATCH,"v1/inbox",beforeRequest:{ request in
          request.headers.bearerAuthorization = .init(token:token)
          try request.content.encode(RewardInboxUpdateRequest(mailIdsToMarkRead:[mail.id]))
        }) { response async throws in
          XCTAssertEqual(response.status,.ok)
          let changed = try response.content.decode(RewardInboxUpdateResponse.self)
          XCTAssertEqual(changed.user.totalExperience,xp)
          if xp == 25 { XCTAssertTrue(changed.inbox[0].read); XCTAssertTrue(changed.inbox[0].rewards.isEmpty) }
          else { XCTAssertTrue(changed.inbox.isEmpty) }
        }
      }
      for body in [#"{"mailIdsToDelete":[]}"#,#"{"mailIdsToMarkRead":null}"#,#"{"xp":999}"#] {
        try await app.test(.PATCH,"v1/inbox",beforeRequest:{ request in
          request.headers.bearerAuthorization = .init(token:owner.accessToken)
          request.headers.contentType = .json; request.body = .init(string:body)
        }) { response async throws in XCTAssertEqual(response.status,.badRequest) }
      }
      try await app.test(.GET,"v1/moderation/weekly-rewards") { response async throws in XCTAssertEqual(response.status,.forbidden) }
      try await app.test(.GET,"v1/moderation/weekly-rewards",beforeRequest:{ $0.headers.add(name:"X-Typebar-Moderation-Key",value:"fixture-moderation") }) { response async throws in
        XCTAssertEqual(response.status,.ok); XCTAssertTrue(try response.content.decode([WeeklyExperienceRewardJob].self).isEmpty)
      }
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
