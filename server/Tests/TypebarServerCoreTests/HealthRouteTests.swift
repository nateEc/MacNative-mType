import XCTVapor
import XCTest

@testable import TypebarServerCore

private actor PasswordResetDeliveryRecorder {
  private var deliveries: [PasswordResetDelivery] = []

  func record(_ delivery: PasswordResetDelivery) { deliveries.append(delivery) }
  func latest() -> PasswordResetDelivery? { deliveries.last }
  func count() -> Int { deliveries.count }
}

final class HealthRouteTests: XCTestCase {
  func testHealthRouteReturnsServiceIdentity() async throws {
    let app = try await Application.make(.testing)

    do {
      try configureTestApp(app)
      try await app.test(.GET, "health") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(
          try response.content.decode(HealthResponse.self),
          HealthResponse(status: "ok", service: "typebar", maintenanceMode: false))
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testCapabilitiesDescribeTheActualServiceScope() async throws {
    let app = try await Application.make(.testing)

    do {
      try configureTestApp(app)
      try await app.test(.GET, "v1/capabilities") { response async in
        XCTAssertEqual(response.status, .ok)
        let capabilities = try? response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertNotNil(capabilities)
        guard let capabilities else { return }
        XCTAssertEqual(capabilities.apiVersion, "v1")
        XCTAssertEqual(capabilities.service, "typebar")
        XCTAssertEqual(capabilities.capabilities["health"], .available)
        XCTAssertEqual(capabilities.capabilities["rateLimiting"], .partial)
        XCTAssertEqual(capabilities.capabilities["authentication"], .available)
        XCTAssertEqual(capabilities.capabilities["passwordReset"], .planned)
        XCTAssertEqual(capabilities.capabilities["synchronization"], .partial)
        XCTAssertEqual(capabilities.capabilities["resultSubmission"], .partial)
        XCTAssertEqual(capabilities.capabilities["leaderboards"], .partial)
        XCTAssertEqual(capabilities.capabilities["profiles"], .partial)
        XCTAssertEqual(capabilities.capabilities["connections"], .partial)
        XCTAssertEqual(capabilities.capabilities["notifications"], .partial)
        XCTAssertEqual(capabilities.capabilities["profileReports"], .partial)
        XCTAssertEqual(capabilities.capabilities["directMessages"], .partial)
        XCTAssertEqual(capabilities.capabilities["experience"], .partial)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testMaintenanceModeKeepsStatusAndReadsAvailableButRejectsWrites() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app, maintenanceMode: true)
      try await app.test(.GET, "health") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(
          try response.content.decode(HealthResponse.self),
          HealthResponse(status: "ok", service: "typebar", maintenanceMode: true))
      }
      try await app.test(.GET, "v1/capabilities") { response async in
        XCTAssertEqual(response.status, .ok)
      }
      try await app.test(.POST, "v1/auth/register") { response async in
        XCTAssertEqual(response.status, .serviceUnavailable)
        XCTAssertEqual(response.headers.first(name: .retryAfter), "300")
        XCTAssertEqual(response.headers.first(name: "X-Typebar-Maintenance"), "true")
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testMaintenanceEnvironmentValuesAreExplicit() {
    XCTAssertTrue(TypebarMaintenanceMode.isEnabled(value: "true"))
    XCTAssertTrue(TypebarMaintenanceMode.isEnabled(value: " ON "))
    XCTAssertFalse(TypebarMaintenanceMode.isEnabled(value: "enabled"))
    XCTAssertFalse(TypebarMaintenanceMode.isEnabled(value: nil))
  }

  func testRegisterAndLoginCreateDistinctSecureSessions() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let registration = try await store.register(
      .init(email: "Me@Example.com", password: "a secure password", displayName: "Typebar User"))
    let login = try await store.login(.init(email: "me@example.com", password: "a secure password"))

    XCTAssertEqual(registration.user.email, "me@example.com")
    XCTAssertEqual(login.user.id, registration.user.id)
    XCTAssertNotEqual(login.accessToken, registration.accessToken)
    XCTAssertEqual(login.accessToken.count, 43)
  }

  func testRateLimiterScopesBucketsAndResetsExpiredWindows() async throws {
    let limiter = RequestRateLimiter()
    let policy = RequestRateLimiter.Policy(id: "test", maximumRequests: 2, window: 60)
    let start = Date(timeIntervalSince1970: 1_000)

    let first = await limiter.evaluate(policy: policy, key: "account-a", now: start)
    let second = await limiter.evaluate(policy: policy, key: "account-a", now: start)
    XCTAssertTrue(first.allowed)
    XCTAssertEqual(second.remaining, 0)
    let denied = await limiter.evaluate(policy: policy, key: "account-a", now: start)
    XCTAssertFalse(denied.allowed)
    XCTAssertEqual(denied.retryAfter, 60)
    let otherAccount = await limiter.evaluate(policy: policy, key: "account-b", now: start)
    let reset = await limiter.evaluate(
      policy: policy, key: "account-a", now: start.addingTimeInterval(60))
    XCTAssertTrue(otherAccount.allowed)
    XCTAssertTrue(reset.allowed)
  }

  func testAuthenticationRoutesReturnRetryAfterWhenRateLimited() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      for number in 0..<10 {
        try await app.test(
          .POST, "v1/auth/register",
          beforeRequest: { request async throws in
            try request.content.encode(
              RegisterRequest(
                email: "rate-\(number)@example.com", password: "a secure password",
                displayName: "Rate User \(number)"))
          },
          afterResponse: { response async in XCTAssertEqual(response.status, .ok) }
        )
      }
      try await app.test(
        .POST, "v1/auth/register",
        beforeRequest: { request async throws in
          try request.content.encode(
            RegisterRequest(
              email: "rate-limited@example.com", password: "a secure password",
              displayName: "Rate Limited"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .tooManyRequests)
          XCTAssertNotNil(response.headers.first(name: .retryAfter))
          XCTAssertEqual(response.headers.first(name: "X-RateLimit-Remaining"), "0")
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testQuoteSubmissionRequiresValidContentAndStartsPending() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "quote@example.com", password: "a secure password", displayName: "Quote User"))
    let other = try await store.register(
      .init(
        email: "quote-other@example.com", password: "a secure password", displayName: "Other User"))
    let submitted = try await store.submitQuote(
      .init(
        language: "english", text: "A quiet practice can make tomorrow easier.",
        attribution: "Typebar contributor"), accessToken: session.accessToken)
    XCTAssertEqual(submitted.status, "pending")
    let spanishSubmission = try await store.submitQuote(
      .init(
        language: "spanish", text: "Una práctica tranquila puede aclarar la mañana siguiente.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(spanishSubmission.status, "pending")
    let germanSubmission = try await store.submitQuote(
      .init(
        language: "german", text: "Eine ruhige Übung macht den nächsten Schritt klarer.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(germanSubmission.status, "pending")
    let frenchSubmission = try await store.submitQuote(
      .init(
        language: "french", text: "Une pratique calme peut éclairer la prochaine étape.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(frenchSubmission.status, "pending")
    let italianSubmission = try await store.submitQuote(
      .init(
        language: "italian", text: "Una pratica calma può chiarire il prossimo passo.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(italianSubmission.status, "pending")
    let portugueseSubmission = try await store.submitQuote(
      .init(
        language: "portuguese", text: "Uma prática calma pode clarear o próximo passo.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(portugueseSubmission.status, "pending")
    _ = try await store.submitQuote(
      .init(language: "english", text: "A steady habit creates useful momentum.", attribution: nil),
      accessToken: other.accessToken)
    let mine = try await store.quoteSubmissions(accessToken: session.accessToken)
    XCTAssertEqual(
      Set(mine.submissions.map(\.id)),
      Set([
        submitted.id, spanishSubmission.id, germanSubmission.id, frenchSubmission.id,
        italianSubmission.id, portugueseSubmission.id,
      ]))
    do {
      try await store.withdrawQuoteSubmission(submitted.id, accessToken: other.accessToken)
      XCTFail("Only the submitting account may withdraw a pending quote")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .profileNotFound) }
    try await store.withdrawQuoteSubmission(submitted.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(spanishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(germanSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(frenchSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(italianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(
      portugueseSubmission.id, accessToken: session.accessToken)
    let mineAfterWithdrawal = try await store.quoteSubmissions(accessToken: session.accessToken)
    XCTAssertTrue(mineAfterWithdrawal.submissions.isEmpty)
    do {
      _ = try await store.submitQuote(
        .init(
          language: "unsupported", text: "A quiet practice can make tomorrow easier.",
          attribution: nil), accessToken: session.accessToken)
      XCTFail("Unsupported quote languages must be rejected")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidQuoteSubmission) }
  }

  func testOnlyApprovedQuotesAreExposedPubliclyAndCanBeModerated() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(
        email: "moderated@example.com", password: "a secure password", displayName: "Moderated User"
      ))
    let submitted = try await store.submitQuote(
      .init(
        language: "english", text: "A careful review keeps a shared practice space useful.",
        attribution: "Typebar community"), accessToken: session.accessToken)

    let beforeApproval = try await store.publicQuotes(language: "english", limit: 10)
    XCTAssertTrue(beforeApproval.quotes.isEmpty)
    let approved = try await store.moderateQuote(submitted.id, status: "approved")
    XCTAssertEqual(approved.status, "approved")
    let reporter = try await store.register(
      .init(
        email: "quote-reporter@example.com", password: "a secure password",
        displayName: "Quote Reporter"))
    let secondRater = try await store.register(
      .init(
        email: "quote-rater@example.com", password: "a secure password", displayName: "Quote Rater")
    )
    let firstRating = try await store.rateQuote(
      submitted.id, request: .init(value: 1), accessToken: reporter.accessToken)
    XCTAssertEqual(firstRating.upvotes, 1)
    XCTAssertEqual(firstRating.downvotes, 0)
    XCTAssertEqual(firstRating.viewerRating, 1)
    let changedRating = try await store.rateQuote(
      submitted.id, request: .init(value: -1), accessToken: reporter.accessToken)
    XCTAssertEqual(changedRating.upvotes, 0)
    XCTAssertEqual(changedRating.downvotes, 1)
    _ = try await store.rateQuote(
      submitted.id, request: .init(value: 1), accessToken: secondRater.accessToken)
    let publicForReporter = try await store.publicQuotes(
      language: "english", limit: 10, accessToken: reporter.accessToken)
    XCTAssertEqual(publicForReporter.quotes.first?.upvotes, 1)
    XCTAssertEqual(publicForReporter.quotes.first?.downvotes, 1)
    XCTAssertEqual(publicForReporter.quotes.first?.viewerRating, -1)
    let clearedRating = try await store.rateQuote(
      submitted.id, request: .init(value: 0), accessToken: reporter.accessToken)
    XCTAssertEqual(clearedRating.viewerRating, nil)
    XCTAssertEqual(clearedRating.downvotes, 0)
    do {
      _ = try await store.rateQuote(
        submitted.id, request: .init(value: 1), accessToken: session.accessToken)
      XCTFail("A quote author may not rate their own quote")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidQuoteSubmission) }
    let report = try await store.submitQuoteReport(
      .init(
        quoteID: submitted.id, reason: .inaccurateAttribution,
        note: "The stated source needs review."), accessToken: reporter.accessToken)
    XCTAssertNotEqual(report.id, UUID())
    let moderationQueue = try await store.moderationQuotes(status: "approved", limit: 10)
    XCTAssertEqual(moderationQueue.quotes.count, 1)
    XCTAssertEqual(moderationQueue.quotes.first?.id, submitted.id)
    XCTAssertEqual(
      moderationQueue.quotes.first?.reports,
      [
        .init(
          reason: .inaccurateAttribution, note: "The stated source needs review.",
          submittedAt: report.submittedAt)
      ])
    let pendingModerationQueue = try await store.moderationQuotes(status: "pending", limit: 10)
    XCTAssertEqual(pendingModerationQueue.quotes.count, 0)
    do {
      _ = try await store.moderationQuotes(status: "hidden", limit: 10)
      XCTFail("Unknown moderation statuses must be rejected")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidQuoteSubmission) }
    do {
      _ = try await store.submitQuoteReport(
        .init(quoteID: submitted.id, reason: .inaccurateAttribution, note: nil),
        accessToken: reporter.accessToken)
      XCTFail("The same reporter may only submit one reason per quote")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .reportAlreadySubmitted) }
    do {
      _ = try await store.submitQuoteReport(
        .init(quoteID: submitted.id, reason: .other, note: nil), accessToken: session.accessToken)
      XCTFail("A quote author may not report their own quote")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .profileNotFound) }
    let publicQuotes = try await store.publicQuotes(language: "english", limit: 10)
    XCTAssertEqual(publicQuotes.quotes.map(\.id), [submitted.id])
    XCTAssertEqual(publicQuotes.quotes.first?.attribution, "Typebar community")
    _ = try await store.moderateQuote(submitted.id, status: "rejected")
    let afterRejection = try await store.publicQuotes(language: "english", limit: 10)
    XCTAssertTrue(afterRejection.quotes.isEmpty)
  }

  func testQuoteSubmissionRouteRequiresAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(.POST, "v1/quotes") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testProfileReportIsPrivateAndRejectsSelfAndDuplicates() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let reporter = try await store.register(
      .init(email: "reporter@example.com", password: "a secure password", displayName: "Reporter"))
    let target = try await store.register(
      .init(email: "target@example.com", password: "a secure password", displayName: "Target"))
    let submitted = try await store.submitProfileReport(
      .init(
        profileID: target.user.id, reason: .suspiciousResults,
        note: "The public scores appear inconsistent."),
      accessToken: reporter.accessToken
    )
    XCTAssertNotEqual(submitted.id, UUID())

    do {
      _ = try await store.submitProfileReport(
        .init(profileID: target.user.id, reason: .suspiciousResults, note: nil),
        accessToken: reporter.accessToken)
      XCTFail("A reporter may only submit one matching report")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .reportAlreadySubmitted)
    }
    do {
      _ = try await store.submitProfileReport(
        .init(profileID: reporter.user.id, reason: .other, note: nil),
        accessToken: reporter.accessToken)
      XCTFail("Accounts must not report themselves")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .cannotReportSelf)
    }
  }

  func testProfileModerationQueueExcludesReporterAndOnlyChangesReviewState() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let reporter = try await store.register(
      .init(
        email: "reviewer-reporter@example.com", password: "a secure password",
        displayName: "Private Reporter"))
    let target = try await store.register(
      .init(
        email: "reviewer-target@example.com", password: "a secure password",
        displayName: "Reported Profile"))
    let submittedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let report = try await store.submitProfileReport(
      .init(
        profileID: target.user.id, reason: .abusiveName, note: "Please review the display name."),
      accessToken: reporter.accessToken,
      now: submittedAt
    )

    let open = await store.moderationProfileReports(status: .open, limit: 10)
    XCTAssertEqual(open.reports.count, 1)
    let queued = try XCTUnwrap(open.reports.first)
    XCTAssertEqual(queued.id, report.id)
    XCTAssertEqual(queued.profile.id, target.user.id)
    XCTAssertEqual(queued.profile.displayName, "Reported Profile")
    XCTAssertEqual(queued.reason, .abusiveName)
    XCTAssertEqual(queued.note, "Please review the display name.")
    XCTAssertEqual(queued.status, .open)

    let dismissed = try await store.moderateProfileReport(report.id, status: .dismissed)
    XCTAssertEqual(dismissed.status, .dismissed)
    let remainingOpen = await store.moderationProfileReports(status: .open, limit: 10)
    let dismissedQueue = await store.moderationProfileReports(status: .dismissed, limit: 10)
    let unchangedProfile = try await store.publicProfile(id: target.user.id)
    XCTAssertTrue(remainingOpen.reports.isEmpty)
    XCTAssertEqual(dismissedQueue.reports.map(\.id), [report.id])
    XCTAssertEqual(unchangedProfile.displayName, "Reported Profile")
  }

  func testProfileModerationRouteRequiresDeploymentKey() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app, moderationKey: "test-profile-moderation-key")
      try await app.test(.GET, "v1/moderation/profile-reports") { response async in
        XCTAssertEqual(response.status, .forbidden)
      }
      try await app.test(
        .GET,
        "v1/moderation/profile-reports?status=open&limit=1",
        beforeRequest: { request async throws in
          request.headers.replaceOrAdd(
            name: "X-Typebar-Moderation-Key", value: "test-profile-moderation-key")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(
            try response.content.decode(ModerationProfileReportListResponse.self).reports, [])
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testProfileReportRouteRequiresAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(
        .POST,
        "v1/reports/profiles",
        beforeRequest: { request async throws in
          try request.content.encode(
            ProfileReportRequest(profileID: UUID(), reason: .other, note: nil))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testDirectMessagesAreFriendScopedReadableAndClearedByBlocking() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(
        email: "message-alice@example.com", password: "a secure password",
        displayName: "Message Alice"))
    let bob = try await store.register(
      .init(
        email: "message-bob@example.com", password: "a secure password", displayName: "Message Bob")
    )
    let charlie = try await store.register(
      .init(
        email: "message-charlie@example.com", password: "a secure password",
        displayName: "Message Charlie"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    do {
      _ = try await store.sendDirectMessage(
        .init(recipientID: bob.user.id, body: "Hello"), accessToken: alice.accessToken, now: now)
      XCTFail("Messages must require an accepted friendship")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .directMessageNotAllowed) }

    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken, now: now)
    _ = try await store.acceptConnection(
      requesterID: alice.user.id, accessToken: bob.accessToken, now: now)
    let sent = try await store.sendDirectMessage(
      .init(recipientID: bob.user.id, body: "  Great pace today.  "),
      accessToken: alice.accessToken, now: now)
    XCTAssertEqual(sent.body, "Great pace today.")
    let bobNotifications = try await store.notifications(accessToken: bob.accessToken, now: now)
    XCTAssertEqual(
      Set(bobNotifications.notifications.map(\.kind)), Set([.connectionRequest, .directMessage]))
    XCTAssertTrue(bobNotifications.notifications.allSatisfy { $0.actor.id == alice.user.id })
    let bobConversation = try await store.directConversation(
      with: alice.user.id, accessToken: bob.accessToken, now: now)
    XCTAssertEqual(bobConversation.messages.map(\.id), [sent.id])
    XCTAssertNil(bobConversation.messages[0].readAt)
    try await store.markDirectConversationRead(
      with: alice.user.id, accessToken: bob.accessToken, now: now.addingTimeInterval(5))
    let readConversation = try await store.directConversation(
      with: alice.user.id, accessToken: bob.accessToken, now: now)
    XCTAssertEqual(readConversation.messages[0].readAt, now.addingTimeInterval(5))

    do {
      _ = try await store.directConversation(
        with: alice.user.id, accessToken: charlie.accessToken, now: now)
      XCTFail("Third parties must not read a conversation")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .directMessageNotAllowed) }
    try await store.blockUser(bob.user.id, accessToken: alice.accessToken, now: now)
    do {
      _ = try await store.directConversation(
        with: bob.user.id, accessToken: alice.accessToken, now: now)
      XCTFail("Blocking must remove access to the conversation")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .directMessageNotAllowed) }
  }

  func testDirectMessageRoutesRequireAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(.GET, "v1/messages/\(UUID().uuidString)") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .POST, "v1/messages",
        beforeRequest: { request async throws in
          try request.content.encode(DirectMessageRequest(recipientID: UUID(), body: "Hello"))
        }, afterResponse: { response async in XCTAssertEqual(response.status, .unauthorized) })
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testRegistrationRejectsDuplicateEmailAndWeakPassword() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let request = RegisterRequest(
      email: "me@example.com", password: "a secure password", displayName: "Typebar User")
    _ = try await store.register(request)

    do {
      _ = try await store.register(request)
      XCTFail("Duplicate registration should fail")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .emailAlreadyRegistered)
    }

    do {
      _ = try await store.register(
        .init(email: "new@example.com", password: "short", displayName: "New User"))
      XCTFail("Weak passwords should fail")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .weakPassword)
    }
  }

  func testPasswordChangeVerifiesCurrentPasswordAndRevokesExistingSessions() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let registration = try await store.register(
      .init(email: "me@example.com", password: "a secure password", displayName: "Typebar User"))
    let secondSession = try await store.login(
      .init(email: "me@example.com", password: "a secure password"))

    do {
      _ = try await store.changePassword(
        .init(currentPassword: "wrong password", newPassword: "a different secure password"),
        accessToken: registration.accessToken)
      XCTFail("Changing a password should require the current password")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }

    let replacement = try await store.changePassword(
      .init(currentPassword: "a secure password", newPassword: "a different secure password"),
      accessToken: registration.accessToken)
    XCTAssertNotEqual(replacement.accessToken, registration.accessToken)

    for token in [registration.accessToken, secondSession.accessToken] {
      do {
        _ = try await store.authenticatedUser(for: token)
        XCTFail("Every pre-change session should be revoked")
      } catch let error as AuthStoreError {
        XCTAssertEqual(error, .invalidAccessToken)
      }
    }
    let authenticatedReplacement = try await store.authenticatedUser(for: replacement.accessToken)
    XCTAssertEqual(authenticatedReplacement.id, registration.user.id)
    _ = try await store.login(
      .init(email: "me@example.com", password: "a different secure password"))
    do {
      _ = try await store.login(.init(email: "me@example.com", password: "a secure password"))
      XCTFail("The old password should no longer authenticate")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }
  }

  func testPasswordRouteRequiresAuthenticationAndReturnsReplacementSession() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "route@example.com", password: "a secure password", displayName: "Route User"))

    do {
      try configure(app, authStore: store)
      try await app.test(.POST, "v1/auth/password") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .POST,
        "v1/auth/password",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(
            ChangePasswordRequest(
              currentPassword: "a secure password", newPassword: "a different secure password"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let replacement = try? response.content.decode(AuthSessionResponse.self)
          XCTAssertEqual(replacement?.user.id, session.user.id)
          XCTAssertNotEqual(replacement?.accessToken, session.accessToken)
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testPasswordResetRevokesSessionsConsumesItsTokenAndExpires() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let start = Date(timeIntervalSince1970: 1_000)
    let registration = try await store.register(
      .init(email: "reset@example.com", password: "a secure password", displayName: "Reset User"),
      now: start)
    let secondSession = try await store.login(
      .init(email: "reset@example.com", password: "a secure password"), now: start)
    let delivery = try await store.requestPasswordReset(for: "RESET@example.com", now: start)
    XCTAssertEqual(delivery?.email, "reset@example.com")
    XCTAssertEqual(delivery?.token.count, 43)

    guard let delivery else { return XCTFail("Known accounts must receive a reset delivery") }
    try await store.completePasswordReset(
      .init(token: delivery.token, newPassword: "a different secure password"),
      now: start.addingTimeInterval(1))
    for token in [registration.accessToken, secondSession.accessToken] {
      do {
        _ = try await store.authenticatedUser(for: token, now: start.addingTimeInterval(1))
        XCTFail("A password reset must revoke every existing session")
      } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidAccessToken) }
    }
    do {
      try await store.completePasswordReset(
        .init(token: delivery.token, newPassword: "another secure password"),
        now: start.addingTimeInterval(2))
      XCTFail("A reset code must only be usable once")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidPasswordResetToken) }
    _ = try await store.login(
      .init(email: "reset@example.com", password: "a different secure password"),
      now: start.addingTimeInterval(2))
    do {
      _ = try await store.login(
        .init(email: "reset@example.com", password: "a secure password"),
        now: start.addingTimeInterval(2))
      XCTFail("The pre-reset password must no longer work")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidCredentials) }

    let expiryDelivery = try await store.requestPasswordReset(for: "reset@example.com", now: start)
    guard let expiryDelivery else { return XCTFail("Known accounts must receive a reset delivery") }
    do {
      try await store.completePasswordReset(
        .init(token: expiryDelivery.token, newPassword: "another secure password"),
        now: start.addingTimeInterval(20 * 60 + 1))
      XCTFail("Expired reset codes must be rejected")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidPasswordResetToken) }
    let unknownDelivery = try await store.requestPasswordReset(for: "unknown@example.com", now: start)
    let malformedDelivery = try await store.requestPasswordReset(for: "not-an-email", now: start)
    XCTAssertNil(unknownDelivery)
    XCTAssertNil(malformedDelivery)
  }

  func testPasswordResetRoutesAvoidAccountEnumerationAndRequireDeliveryConfiguration() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let recorder = PasswordResetDeliveryRecorder()
    _ = try await store.register(
      .init(email: "route-reset@example.com", password: "a secure password", displayName: "Route Reset"))

    do {
      try configure(
        app,
        authStore: store,
        passwordResetDelivery: { delivery in await recorder.record(delivery) })
      try await app.test(.GET, "v1/capabilities") { response async in
        let capabilities = try? response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(capabilities?.capabilities["passwordReset"], .available)
      }
      try await app.test(
        .POST,
        "v1/auth/password-reset/request",
        beforeRequest: { request async throws in
          try request.content.encode(PasswordResetRequest(email: "route-reset@example.com"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(try? response.content.decode(PasswordResetRequestResponse.self), .init(accepted: true))
        }
      )
      try await app.test(
        .POST,
        "v1/auth/password-reset/request",
        beforeRequest: { request async throws in
          try request.content.encode(PasswordResetRequest(email: "unknown@example.com"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(try? response.content.decode(PasswordResetRequestResponse.self), .init(accepted: true))
        }
      )
      let deliveryCount = await recorder.count()
      XCTAssertEqual(deliveryCount, 1)
      guard let delivery = await recorder.latest() else {
        return XCTFail("The configured delivery handler should receive the opaque token")
      }
      try await app.test(
        .POST,
        "v1/auth/password-reset/complete",
        beforeRequest: { request async throws in
          try request.content.encode(
            CompletePasswordResetRequest(token: delivery.token, newPassword: "a different secure password"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(try? response.content.decode(PasswordResetCompletionResponse.self), .init(reset: true))
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }

    let unavailableApp = try await Application.make(.testing)
    do {
      try configureTestApp(unavailableApp)
      try await unavailableApp.test(
        .POST,
        "v1/auth/password-reset/request",
        beforeRequest: { request async throws in
          try request.content.encode(PasswordResetRequest(email: "any@example.com"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .serviceUnavailable)
        }
      )
      try await unavailableApp.asyncShutdown()
    } catch {
      try? await unavailableApp.asyncShutdown()
      throw error
    }
  }

  func testEmailChangeVerifiesPasswordAvoidsDuplicatesAndRevokesSessions() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let registration = try await store.register(
      .init(email: "old@example.com", password: "a secure password", displayName: "Email User"))
    let secondSession = try await store.login(
      .init(email: "old@example.com", password: "a secure password"))
    _ = try await store.register(
      .init(email: "taken@example.com", password: "a secure password", displayName: "Other User"))

    do {
      _ = try await store.changeEmail(
        .init(currentPassword: "wrong password", newEmail: "new@example.com"),
        accessToken: registration.accessToken)
      XCTFail("Changing an email should require the current password")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }
    do {
      _ = try await store.changeEmail(
        .init(currentPassword: "a secure password", newEmail: "taken@example.com"),
        accessToken: registration.accessToken)
      XCTFail("Changing to an existing email must fail")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .emailAlreadyRegistered)
    }

    let replacement = try await store.changeEmail(
      .init(currentPassword: "a secure password", newEmail: "new@example.com"),
      accessToken: registration.accessToken)
    XCTAssertEqual(replacement.user.email, "new@example.com")
    for token in [registration.accessToken, secondSession.accessToken] {
      do {
        _ = try await store.authenticatedUser(for: token)
        XCTFail("Every pre-change session should be revoked")
      } catch let error as AuthStoreError {
        XCTAssertEqual(error, .invalidAccessToken)
      }
    }
    _ = try await store.login(.init(email: "new@example.com", password: "a secure password"))
    do {
      _ = try await store.login(.init(email: "old@example.com", password: "a secure password"))
      XCTFail("The previous email should no longer sign in")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }
  }

  func testEmailChangeRouteRequiresAuthenticationAndReturnsReplacementSession() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(
        email: "email-route@example.com", password: "a secure password", displayName: "Route User"))

    do {
      try configure(app, authStore: store)
      try await app.test(
        .POST,
        "v1/auth/email",
        beforeRequest: { request async throws in
          try request.content.encode(
            ChangeEmailRequest(
              currentPassword: "a secure password", newEmail: "updated-route@example.com"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        }
      )
      try await app.test(
        .POST,
        "v1/auth/email",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(
            ChangeEmailRequest(
              currentPassword: "a secure password", newEmail: "updated-route@example.com"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let replacement = try? response.content.decode(AuthSessionResponse.self)
          XCTAssertEqual(replacement?.user.email, "updated-route@example.com")
          XCTAssertNotEqual(replacement?.accessToken, session.accessToken)
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testAccountDeletionRequiresPasswordAndCascadesOwnedData() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(email: "delete-alice@example.com", password: "a secure password", displayName: "Alice"))
    let bob = try await store.register(
      .init(email: "delete-bob@example.com", password: "a secure password", displayName: "Bob"))
    let now = Date.now
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 81, accuracy: 99, finishedAt: now), accessToken: alice.accessToken,
      now: now)
    _ = try await store.pushSync(
      .init(changes: [
        .init(id: UUID(), type: "preset", version: 1, payload: "{}", isDeleted: false)
      ]), accessToken: alice.accessToken, now: now)
    _ = try await store.submitQuote(
      .init(
        language: "english", text: "A deliberate practice builds durable confidence.",
        attribution: nil), accessToken: alice.accessToken, now: now)
    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken, now: now)
    _ = try await store.acceptConnection(
      requesterID: alice.user.id, accessToken: bob.accessToken, now: now)
    try await store.blockUser(alice.user.id, accessToken: bob.accessToken, now: now)
    let blocksBeforeDeletion = try await store.blockedUsers(accessToken: bob.accessToken, now: now)
    XCTAssertEqual(blocksBeforeDeletion.profiles.map(\.id), [alice.user.id])

    do {
      try await store.deleteAccount(
        .init(currentPassword: "wrong password"), accessToken: alice.accessToken, now: now)
      XCTFail("Account deletion must require the current password")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }

    try await store.deleteAccount(
      .init(currentPassword: "a secure password"), accessToken: alice.accessToken, now: now)
    do {
      _ = try await store.authenticatedUser(for: alice.accessToken, now: now)
      XCTFail("Deleted account sessions must no longer authenticate")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidAccessToken)
    }
    do {
      _ = try await store.publicProfile(id: alice.user.id)
      XCTFail("Deleted accounts must not remain public")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .profileNotFound)
    }
    let leaderboardAfterDeletion = try await store.leaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), now: now)
    let connectionsAfterDeletion = try await store.connections(
      accessToken: bob.accessToken, now: now)
    let blocksAfterDeletion = try await store.blockedUsers(accessToken: bob.accessToken, now: now)
    let bobSyncAfterDeletion = try await store.pullSync(
      after: 0, accessToken: bob.accessToken, now: now)
    XCTAssertTrue(leaderboardAfterDeletion.entries.isEmpty)
    XCTAssertTrue(connectionsAfterDeletion.connections.isEmpty)
    XCTAssertTrue(blocksAfterDeletion.profiles.isEmpty)
    XCTAssertTrue(bobSyncAfterDeletion.changes.isEmpty)
    _ = try await store.register(
      .init(
        email: "delete-alice@example.com", password: "a different secure password",
        displayName: "New Alice"), now: now)
  }

  func testAccountDeletionRouteRequiresAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(.DELETE, "v1/auth/account") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testRegisterRouteReturnsCreatedSession() async throws {
    let app = try await Application.make(.testing)

    do {
      try configureTestApp(app)
      try await app.test(
        .POST,
        "v1/auth/register",
        beforeRequest: { request async throws in
          try request.content.encode(
            RegisterRequest(
              email: "new@example.com", password: "a secure password", displayName: "New User"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let session = try? response.content.decode(AuthSessionResponse.self)
          XCTAssertEqual(session?.user.email, "new@example.com")
          XCTAssertEqual(session?.user.displayName, "New User")
          XCTAssertFalse(session?.accessToken.isEmpty ?? true)
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testProfileRoutesRequireTokenAndPersistDisplayName() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "me@example.com", password: "a secure password", displayName: "Original Name"))

    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/me") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .PATCH,
        "v1/profiles/me",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(UpdateProfileRequest(displayName: "Updated Name"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(
            (try? response.content.decode(AuthUserResponse.self))?.displayName, "Updated Name")
        }
      )
      try await app.test(
        .GET,
        "v1/profiles/me",
        beforeRequest: { request async in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(
            (try? response.content.decode(AuthUserResponse.self))?.displayName, "Updated Name")
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testPublicProfileHidesEmailAndIncludesAggregateResults() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(
        email: "private@example.com", password: "a secure password", displayName: "Profile User"))
    let now = Date.now
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 88, accuracy: 99, consistency: 84, finishedAt: now), accessToken: session.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 76, accuracy: 98, consistency: 92, finishedAt: now), accessToken: session.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(
        id: UUID(), wpm: 72, accuracy: 97, consistency: 88, durationSeconds: 15,
        finishedAt: now), accessToken: session.accessToken, now: now)
    _ = try await store.submitResult(
      result(
        id: UUID(), wpm: 66, accuracy: 96, consistency: 75, mode: "words",
        durationSeconds: nil, wordLimit: 10, finishedAt: now), accessToken: session.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(
        id: UUID(), wpm: 55, accuracy: 95, consistency: 70,
        finishedAt: now.addingTimeInterval(-366 * 24 * 60 * 60)), accessToken: session.accessToken,
      now: now)
    let detailedProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(detailedProfile.activity?.testsByDays.count, 365)
    XCTAssertEqual(detailedProfile.activity?.testsByDays.reduce(0, +), 4)
    XCTAssertEqual(detailedProfile.activity?.testsByDays.last, 4)

    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/\(session.user.id.uuidString)") { response async in
        XCTAssertEqual(response.status, .ok)
        let profile = try? response.content.decode(PublicProfileResponse.self)
        XCTAssertEqual(profile?.displayName, "Profile User")
        XCTAssertEqual(profile?.completedResultCount, 5)
        XCTAssertEqual(profile?.bestWPM, 88)
        XCTAssertEqual(profile?.highestConsistency, 92)
        XCTAssertEqual(profile?.personalBests.map(\.durationSeconds), [15, 30, nil])
        XCTAssertEqual(profile?.personalBests.map(\.wordLimit), [nil, nil, 10])
        XCTAssertEqual(profile?.personalBests.map(\.wpm), [72, 88, 66])
        XCTAssertEqual(profile?.personalBests.map(\.consistency), [88, 84, 75])
        XCTAssertEqual(profile?.activity?.testsByDays.count, 365)
        XCTAssertEqual(profile?.activity?.testsByDays.reduce(0, +), 4)
        XCTAssertFalse(response.body.string.contains("private@example.com"))
      }
      try await app.test(.GET, "v1/profiles/not-a-uuid") { response async in
        XCTAssertEqual(response.status, .badRequest)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testConnectionsSupportRequestsAcceptanceAndUserScopedLists() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(email: "alice@example.com", password: "a secure password", displayName: "Alice"))
    let bob = try await store.register(
      .init(email: "bob@example.com", password: "a secure password", displayName: "Bob"))
    let charlie = try await store.register(
      .init(email: "charlie@example.com", password: "a secure password", displayName: "Charlie"))

    let request = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken)
    XCTAssertEqual(request.relation, .outgoingRequest)
    XCTAssertEqual(request.profile.displayName, "Bob")
    let bobIncoming = try await store.connections(accessToken: bob.accessToken)
    XCTAssertEqual(bobIncoming.connections.first?.relation, .incomingRequest)
    let charlieConnections = try await store.connections(accessToken: charlie.accessToken)
    XCTAssertEqual(charlieConnections.connections.count, 0)

    let accepted = try await store.acceptConnection(
      requesterID: alice.user.id, accessToken: bob.accessToken)
    XCTAssertEqual(accepted.relation, .friend)
    let aliceFriends = try await store.connections(accessToken: alice.accessToken)
    XCTAssertEqual(aliceFriends.connections.first?.relation, .friend)

    do {
      _ = try await store.sendConnection(
        .init(recipientID: alice.user.id), accessToken: alice.accessToken)
      XCTFail("Users must not connect to themselves")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .cannotConnectToSelf)
    }

    try await store.removeConnection(otherUserID: bob.user.id, accessToken: alice.accessToken)
    let bobAfterRemoval = try await store.connections(accessToken: bob.accessToken)
    XCTAssertTrue(bobAfterRemoval.connections.isEmpty)
  }

  func testConnectionEventsCreateUserScopedReadableNotifications() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(
        email: "notice-alice@example.com", password: "a secure password",
        displayName: "Notice Alice"))
    let bob = try await store.register(
      .init(
        email: "notice-bob@example.com", password: "a secure password", displayName: "Notice Bob"))
    let charlie = try await store.register(
      .init(
        email: "notice-charlie@example.com", password: "a secure password",
        displayName: "Notice Charlie"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken, now: now)
    let bobNotifications = try await store.notifications(accessToken: bob.accessToken, now: now)
    XCTAssertEqual(bobNotifications.notifications.count, 1)
    XCTAssertEqual(bobNotifications.notifications[0].kind, .connectionRequest)
    XCTAssertEqual(bobNotifications.notifications[0].actor.id, alice.user.id)
    XCTAssertNil(bobNotifications.notifications[0].readAt)
    let charlieNotifications = try await store.notifications(
      accessToken: charlie.accessToken, now: now)
    XCTAssertTrue(charlieNotifications.notifications.isEmpty)

    do {
      _ = try await store.markNotificationRead(
        bobNotifications.notifications[0].id, accessToken: charlie.accessToken, now: now)
      XCTFail("Only a notification recipient may mark it as read")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .notificationNotFound)
    }

    let read = try await store.markNotificationRead(
      bobNotifications.notifications[0].id, accessToken: bob.accessToken,
      now: now.addingTimeInterval(5))
    XCTAssertEqual(read.readAt, now.addingTimeInterval(5))
    _ = try await store.acceptConnection(
      requesterID: alice.user.id, accessToken: bob.accessToken, now: now.addingTimeInterval(10))
    let aliceNotifications = try await store.notifications(
      accessToken: alice.accessToken, now: now.addingTimeInterval(10))
    XCTAssertEqual(aliceNotifications.notifications.map(\.kind), [.connectionAccepted])
    XCTAssertEqual(aliceNotifications.notifications[0].actor.id, bob.user.id)
  }

  func testNotificationRoutesRequireAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(.GET, "v1/notifications") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.POST, "v1/notifications/not-a-uuid/read") { response async in
        XCTAssertEqual(response.status, .badRequest)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testFriendLeaderboardIncludesOnlyCurrentUserAndAcceptedFriends() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(email: "rank-alice@example.com", password: "a secure password", displayName: "Alice"))
    let bob = try await store.register(
      .init(email: "rank-bob@example.com", password: "a secure password", displayName: "Bob"))
    let charlie = try await store.register(
      .init(
        email: "rank-charlie@example.com", password: "a secure password", displayName: "Charlie"))
    let now = Date.now
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 72, accuracy: 98, finishedAt: now), accessToken: alice.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 91, accuracy: 99, finishedAt: now), accessToken: bob.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 140, accuracy: 100, finishedAt: now),
      accessToken: charlie.accessToken, now: now)

    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken, now: now)
    _ = try await store.acceptConnection(
      requesterID: alice.user.id, accessToken: bob.accessToken, now: now)
    _ = try await store.sendConnection(
      .init(recipientID: charlie.user.id), accessToken: alice.accessToken, now: now)

    let entries = try await store.friendLeaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), accessToken: alice.accessToken,
      now: now
    ).entries
    XCTAssertEqual(entries.map(\.displayName), ["Bob", "Alice"])
    XCTAssertEqual(entries.map(\.rank), [1, 2])
  }

  func testFriendLeaderboardRouteRequiresAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(.GET, "v1/leaderboards/friends") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testLeaderboardOptOutImmediatelyHidesAccountFromEveryLeaderboard() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let alice = try await store.register(
      .init(email: "private-rank@example.com", password: "a secure password", displayName: "Private Rank"),
      now: now)
    let bob = try await store.register(
      .init(email: "public-rank@example.com", password: "a secure password", displayName: "Public Rank"),
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 120, accuracy: 100, finishedAt: now), accessToken: alice.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 100, accuracy: 100, finishedAt: now), accessToken: bob.accessToken,
      now: now)
    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken, now: now)
    _ = try await store.acceptConnection(
      requesterID: alice.user.id, accessToken: bob.accessToken, now: now)

    let updated = try await store.updateProfile(
      .init(displayName: alice.user.displayName, leaderboardOptedOut: true),
      accessToken: alice.accessToken, now: now)
    XCTAssertTrue(updated.leaderboardOptedOut)
    let globalEntries = try await store.leaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), now: now).entries
    let friendEntries = try await store.friendLeaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), accessToken: bob.accessToken,
      now: now).entries
    let globalXPEntries = await store.experienceLeaderboard(now: now).entries
    let friendXPEntries = try await store.friendExperienceLeaderboard(
      accessToken: bob.accessToken, now: now).entries
    XCTAssertEqual(globalEntries.map(\.userID), [bob.user.id])
    XCTAssertEqual(friendEntries.map(\.userID), [bob.user.id])
    XCTAssertTrue(globalXPEntries.allSatisfy { $0.userID != alice.user.id })
    XCTAssertTrue(friendXPEntries.allSatisfy { $0.userID != alice.user.id })

    let submission = try await store.submitResult(
      result(id: UUID(), wpm: 110, accuracy: 100, finishedAt: now), accessToken: alice.accessToken,
      now: now)
    XCTAssertFalse(submission.leaderboardEligible)
    XCTAssertNil(submission.weeklyExperienceRank)
    XCTAssertGreaterThan(submission.totalExperience, 0)
  }

  func testBlockingRemovesExistingConnectionAndRejectsRequestsInEitherDirection() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(
        email: "block-alice@example.com", password: "a secure password", displayName: "Block Alice")
    )
    let bob = try await store.register(
      .init(email: "block-bob@example.com", password: "a secure password", displayName: "Block Bob")
    )
    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken)

    try await store.blockUser(bob.user.id, accessToken: alice.accessToken)
    let aliceConnections = try await store.connections(accessToken: alice.accessToken)
    let bobConnections = try await store.connections(accessToken: bob.accessToken)
    XCTAssertTrue(aliceConnections.connections.isEmpty)
    XCTAssertTrue(bobConnections.connections.isEmpty)
    let blockedBeforeUnblock = try await store.blockedUsers(accessToken: alice.accessToken)
    XCTAssertEqual(blockedBeforeUnblock.profiles.map(\.id), [bob.user.id])
    for (token, recipient) in [(alice.accessToken, bob.user.id), (bob.accessToken, alice.user.id)] {
      do {
        _ = try await store.sendConnection(.init(recipientID: recipient), accessToken: token)
        XCTFail("Blocking must reject connection requests in either direction")
      } catch let error as AuthStoreError {
        XCTAssertEqual(error, .connectionNotFound)
      }
    }
    try await store.unblockUser(bob.user.id, accessToken: alice.accessToken)
    let blockedAfterUnblock = try await store.blockedUsers(accessToken: alice.accessToken)
    XCTAssertTrue(blockedAfterUnblock.profiles.isEmpty)
    _ = try await store.sendConnection(
      .init(recipientID: bob.user.id), accessToken: alice.accessToken)
  }

  func testPublicProfileSearchUsesDisplayNamesWithoutExposingEmails() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    _ = try await store.register(
      .init(
        email: "ada.private@example.com", password: "a secure password", displayName: "Ada Typist"))
    _ = try await store.register(
      .init(email: "alex.private@example.com", password: "a secure password", displayName: "Alex"))

    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles?query=ada") { response async in
        XCTAssertEqual(response.status, .ok)
        let results = try? response.content.decode(PublicProfileSearchResponse.self)
        XCTAssertEqual(results?.profiles.map(\.displayName), ["Ada Typist"])
        XCTAssertNil(results?.profiles.first?.activity)
        XCTAssertFalse(response.body.string.contains("ada.private@example.com"))
      }
      try await app.test(.GET, "v1/profiles?query=x") { response async in
        XCTAssertEqual(response.status, .badRequest)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testSyncUsesUserScopedVersionsAndCursors() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(
      .init(email: "owner@example.com", password: "a secure password", displayName: "Owner"))
    let other = try await store.register(
      .init(email: "other@example.com", password: "a secure password", displayName: "Other"))
    let id = UUID()

    let firstPush = try await store.pushSync(
      .init(changes: [
        .init(
          id: id, type: "preset", version: 1, payload: "{\"name\":\"focused\"}", isDeleted: false)
      ]),
      accessToken: owner.accessToken
    )
    XCTAssertEqual(firstPush.results, [.init(id: id, status: .accepted, serverVersion: 1)])
    XCTAssertEqual(firstPush.nextCursor, 1)

    let conflict = try await store.pushSync(
      .init(changes: [.init(id: id, type: "preset", version: 1, payload: "{}", isDeleted: false)]),
      accessToken: owner.accessToken
    )
    XCTAssertEqual(conflict.results, [.init(id: id, status: .conflict, serverVersion: 1)])

    let update = try await store.pushSync(
      .init(changes: [.init(id: id, type: "preset", version: 2, payload: nil, isDeleted: true)]),
      accessToken: owner.accessToken
    )
    XCTAssertEqual(update.nextCursor, 2)

    let ownerChanges = try await store.pullSync(after: 1, accessToken: owner.accessToken)
    XCTAssertEqual(ownerChanges.changes.count, 1)
    XCTAssertEqual(ownerChanges.changes[0].version, 2)
    XCTAssertTrue(ownerChanges.changes[0].isDeleted)

    let otherChanges = try await store.pullSync(after: 0, accessToken: other.accessToken)
    XCTAssertTrue(otherChanges.changes.isEmpty)
  }

  func testSyncPullPagesUserChangesWithoutSkippingTheFinalCursor() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(
      .init(email: "paged-owner@example.com", password: "a secure password", displayName: "Owner"))
    let other = try await store.register(
      .init(email: "paged-other@example.com", password: "a secure password", displayName: "Other"))
    let ownerIDs = [UUID(), UUID(), UUID()]

    for id in ownerIDs {
      _ = try await store.pushSync(
        .init(changes: [.init(id: id, type: "preset", version: 1, payload: "{}", isDeleted: false)]),
        accessToken: owner.accessToken)
    }
    _ = try await store.pushSync(
      .init(changes: [.init(id: UUID(), type: "preset", version: 1, payload: "{}", isDeleted: false)]),
      accessToken: other.accessToken)

    let firstPage = try await store.pullSync(after: 0, accessToken: owner.accessToken, limit: 2)
    XCTAssertEqual(firstPage.changes.map(\.id), Array(ownerIDs.prefix(2)))
    XCTAssertEqual(firstPage.nextCursor, 2)
    XCTAssertTrue(firstPage.hasMore)

    let finalPage = try await store.pullSync(
      after: firstPage.nextCursor, accessToken: owner.accessToken, limit: 2)
    XCTAssertEqual(finalPage.changes.map(\.id), [ownerIDs[2]])
    XCTAssertEqual(finalPage.nextCursor, 4)
    XCTAssertFalse(finalPage.hasMore)

    let caughtUp = try await store.pullSync(
      after: finalPage.nextCursor, accessToken: owner.accessToken, limit: 2)
    XCTAssertTrue(caughtUp.changes.isEmpty)
    XCTAssertEqual(caughtUp.nextCursor, 4)
    XCTAssertFalse(caughtUp.hasMore)
  }

  func testResultsAreIdempotentAndLeaderboardOrdersEligibleScores() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let slower = try await store.register(
      .init(email: "slower@example.com", password: "a secure password", displayName: "Slower"))
    let faster = try await store.register(
      .init(email: "faster@example.com", password: "a secure password", displayName: "Faster"))
    let now = Date.now
    let firstID = UUID()

    let first = try await store.submitResult(
      result(id: firstID, wpm: 74, accuracy: 98, finishedAt: now), accessToken: slower.accessToken,
      now: now)
    let duplicate = try await store.submitResult(
      result(id: firstID, wpm: 74, accuracy: 98, finishedAt: now), accessToken: slower.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 101, accuracy: 96, consistency: 94, finishedAt: now), accessToken: faster.accessToken,
      now: now)

    XCTAssertTrue(first.accepted)
    XCTAssertTrue(duplicate.accepted)
    _ = try await store.submitResult(
      result(
        id: UUID(), wpm: 80, accuracy: 99, consistency: 77,
        finishedAt: now.addingTimeInterval(1)),
      accessToken: slower.accessToken, now: now)
    let response = try await store.leaderboard(
      .init(mode: "time", language: "english", period: "all", limit: 10))
    XCTAssertEqual(response.entries.map(\.displayName), ["Faster", "Slower"])
    XCTAssertEqual(response.entries.map(\.rank), [1, 2])
    XCTAssertEqual(response.entries.map(\.wpm), [101, 80])
    XCTAssertEqual(response.entries.map(\.consistency), [94, 77])
    XCTAssertEqual(response.entries.map(\.id).count, Set(response.entries.map(\.id)).count)
  }

  func testResultSubmissionDefaultsMissingConsistencyForLegacyClient() throws {
    let id = UUID()
    let payload = """
      {"id":"\(id.uuidString)","mode":"time","language":"english","durationSeconds":30,"wpm":80,"rawWpm":80,"accuracy":100,"errorCount":0,"eventCount":200,"startedAt":1000,"finishedAt":1030}
      """

    let request = try JSONDecoder().decode(ResultSubmissionRequest.self, from: Data(payload.utf8))

    XCTAssertEqual(request.consistency, 0)
  }

  func testExperienceIsServerCalculatedIdempotentAndRankedForTheCurrentISOWeek() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let alice = try await store.register(
      .init(email: "xp-alice@example.com", password: "a secure password", displayName: "XP Alice"))
    let bob = try await store.register(
      .init(email: "xp-bob@example.com", password: "a secure password", displayName: "XP Bob"))
    let now = Date.now
    let aliceRequest = result(id: UUID(), wpm: 80, accuracy: 100, finishedAt: now)
    let aliceResponse = try await store.submitResult(
      aliceRequest, accessToken: alice.accessToken, now: now)
    XCTAssertEqual(
      aliceResponse.experienceGained, TypebarExperiencePolicy.points(for: aliceRequest))
    XCTAssertEqual(aliceResponse.totalExperience, aliceResponse.experienceGained)
    XCTAssertEqual(aliceResponse.weeklyExperienceRank, 1)

    let duplicate = try await store.submitResult(
      aliceRequest, accessToken: alice.accessToken, now: now)
    XCTAssertEqual(duplicate.experienceGained, aliceResponse.experienceGained)
    XCTAssertEqual(duplicate.totalExperience, aliceResponse.totalExperience)

    let bobRequest = result(id: UUID(), wpm: 65, accuracy: 90, finishedAt: now)
    _ = try await store.submitResult(bobRequest, accessToken: bob.accessToken, now: now)
    let weekly = await store.experienceLeaderboard(now: now)
    XCTAssertEqual(weekly.entries.map(\.displayName), ["XP Alice", "XP Bob"])
    XCTAssertEqual(
      weekly.entries.map(\.totalExperience),
      [aliceResponse.totalExperience, TypebarExperiencePolicy.points(for: bobRequest)])

    let zen = ResultSubmissionRequest(
      id: UUID(), mode: "zen", language: "english", durationSeconds: nil, wordLimit: nil, wpm: 80,
      rawWpm: 80, accuracy: 100, errorCount: 0, eventCount: 60,
      startedAt: now.addingTimeInterval(-9), finishedAt: now)
    XCTAssertEqual(TypebarExperiencePolicy.points(for: zen), 0)
  }

  func testResultsRejectImpossibleOrMalformedValues() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "me@example.com", password: "a secure password", displayName: "Typebar User"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    do {
      _ = try await store.submitResult(
        result(id: UUID(), wpm: 401, accuracy: 100, finishedAt: now),
        accessToken: session.accessToken, now: now)
      XCTFail("Out-of-bounds WPM must be rejected")
    } catch let error as ResultStoreError {
      XCTAssertEqual(error, .invalidResult)
    }

    do {
      _ = try await store.submitResult(
        result(id: UUID(), wpm: 80, accuracy: 100, consistency: 101, finishedAt: now),
        accessToken: session.accessToken, now: now)
      XCTFail("Out-of-bounds consistency must be rejected")
    } catch let error as ResultStoreError {
      XCTAssertEqual(error, .invalidResult)
    }

    let inconsistent = ResultSubmissionRequest(
      id: UUID(), mode: "time", language: "english", durationSeconds: 30, wordLimit: nil,
      wpm: 20, rawWpm: 20, accuracy: 100, errorCount: 0, eventCount: 50,
      startedAt: now.addingTimeInterval(-30), finishedAt: now
    )
    _ = try await store.submitResult(inconsistent, accessToken: session.accessToken, now: now)
    let forgedAccuracy = ResultSubmissionRequest(
      id: UUID(), mode: "time", language: "english", durationSeconds: 30, wordLimit: nil,
      wpm: 20, rawWpm: 20, accuracy: 100, errorCount: 5, eventCount: 50,
      startedAt: now.addingTimeInterval(-30), finishedAt: now
    )
    do {
      _ = try await store.submitResult(forgedAccuracy, accessToken: session.accessToken, now: now)
      XCTFail("A result whose accuracy conflicts with its input count must be rejected")
    } catch let error as ResultStoreError {
      XCTAssertEqual(error, .invalidResult)
    }

    do {
      _ = try await store.leaderboard(
        .init(mode: "not-a-mode", language: nil, period: "all", limit: 10))
      XCTFail("Unknown leaderboard filter must be rejected")
    } catch let error as ResultStoreError {
      XCTAssertEqual(error, .invalidResult)
    }
  }

  func testResultRoutesRequireAuthenticationAndReturnLeaderboard() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "me@example.com", password: "a secure password", displayName: "Route User"))
    let now = Date.now

    do {
      try configure(app, authStore: store)
      try await app.test(.POST, "v1/results") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .POST, "v1/results",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(result(id: UUID(), wpm: 88, accuracy: 99, finishedAt: now))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertTrue(
            (try? response.content.decode(ResultSubmissionResponse.self))?.leaderboardEligible
              ?? false)
        })
      try await app.test(.GET, "v1/leaderboards?mode=time&language=english") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(
          (try? response.content.decode(LeaderboardResponse.self))?.entries.first?.displayName,
          "Route User")
      }
      try await app.test(.GET, "v1/leaderboards/experience") { response async in
        XCTAssertEqual(response.status, .ok)
        let entries = try? response.content.decode(ExperienceLeaderboardResponse.self).entries
        XCTAssertEqual(entries?.first?.displayName, "Route User")
        XCTAssertTrue((entries?.first?.totalExperience ?? 0) > 0)
      }
      try await app.test(.GET, "v1/leaderboards/experience/friends") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testLeaderboardPeriodsUseTodayAndISOWeekBoundaries() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "period@example.com", password: "a secure password", displayName: "Period User"))
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z"))
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 80, accuracy: 99, finishedAt: now), accessToken: session.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 90, accuracy: 99, finishedAt: now.addingTimeInterval(-60 * 60 * 25)),
      accessToken: session.accessToken, now: now)
    _ = try await store.submitResult(
      result(
        id: UUID(), wpm: 100, accuracy: 99, finishedAt: now.addingTimeInterval(-60 * 60 * 24 * 8)),
      accessToken: session.accessToken, now: now)

    let today = try await store.leaderboard(
      .init(mode: "time", language: "english", period: "day", limit: 10), now: now)
    let week = try await store.leaderboard(
      .init(mode: "time", language: "english", period: "week", limit: 10), now: now)
    XCTAssertEqual(today.entries.map(\.wpm), [80])
    XCTAssertEqual(week.entries.map(\.wpm), [90])
  }

  private func result(
    id: UUID, wpm: Int, accuracy: Int, consistency: Double = 0, mode: String = "time",
    durationSeconds: Int? = 30, wordLimit: Int? = nil, finishedAt: Date
  )
    -> ResultSubmissionRequest
  {
    let elapsed = Double(durationSeconds ?? 30)
    let correctCharacters = max(1, Int((Double(wpm) * 5 * elapsed / 60).rounded()))
    let lowerBound = max(correctCharacters, 1)
    let eventCount =
      (lowerBound...(lowerBound + 1_000)).first {
        Int((Double(correctCharacters) / Double($0) * 100).rounded()) == accuracy
      } ?? lowerBound
    let rawWpm = Int((Double(eventCount) / 5 / elapsed * 60).rounded())
    return .init(
      id: id, mode: mode, language: "english", durationSeconds: durationSeconds, wordLimit: wordLimit,
      wpm: wpm, rawWpm: rawWpm, accuracy: accuracy, consistency: consistency,
      errorCount: eventCount - correctCharacters, eventCount: eventCount,
      startedAt: finishedAt.addingTimeInterval(-elapsed),
      finishedAt: finishedAt)
  }

  private func configureTestApp(
    _ app: Application,
    moderationKey: String? = nil,
    maintenanceMode: Bool = false
  ) throws {
    try configure(
      app,
      authStore: AuthStore(fileURL: nil, bcryptCost: 4),
      moderationKey: moderationKey,
      maintenanceMode: maintenanceMode)
  }
}
