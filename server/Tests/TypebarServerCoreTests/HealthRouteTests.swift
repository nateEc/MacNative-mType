import XCTVapor
import XCTest

@testable import TypebarServerCore

private actor PasswordResetDeliveryRecorder {
  private var deliveries: [PasswordResetDelivery] = []

  func record(_ delivery: PasswordResetDelivery) { deliveries.append(delivery) }
  func latest() -> PasswordResetDelivery? { deliveries.last }
  func count() -> Int { deliveries.count }
}

private actor EmailVerificationDeliveryRecorder {
  private var deliveries: [EmailVerificationDelivery] = []

  func record(_ delivery: EmailVerificationDelivery) { deliveries.append(delivery) }
  func latest() -> EmailVerificationDelivery? { deliveries.last }
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
        XCTAssertEqual(capabilities.capabilities["developerAccessKeys"], .partial)
        XCTAssertEqual(capabilities.capabilities["passwordReset"], .planned)
        XCTAssertEqual(capabilities.capabilities["emailVerification"], .planned)
        XCTAssertEqual(capabilities.capabilities["synchronization"], .partial)
        XCTAssertEqual(capabilities.capabilities["resultSubmission"], .partial)
        XCTAssertEqual(capabilities.capabilities["resultHistory"], .partial)
        XCTAssertEqual(capabilities.capabilities["leaderboards"], .partial)
        XCTAssertEqual(capabilities.capabilities["profiles"], .partial)
        XCTAssertEqual(capabilities.capabilities["connections"], .partial)
        XCTAssertEqual(capabilities.capabilities["notifications"], .partial)
        XCTAssertEqual(capabilities.capabilities["profileReports"], .partial)
        XCTAssertEqual(capabilities.capabilities["directMessages"], .partial)
        XCTAssertEqual(capabilities.capabilities["experience"], .partial)
        XCTAssertEqual(capabilities.capabilities["announcements"], .available)
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

  func testPublicAnnouncementsCanBePublishedAndRemovedOnlyWithDeploymentKey() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app, moderationKey: "test-announcement-key")
      try await app.test(.GET, "v1/announcements") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try response.content.decode(PublicAnnouncementsResponse.self).announcements, [])
      }
      try await app.test(.POST, "v1/moderation/announcements") { response async in
        XCTAssertEqual(response.status, .forbidden)
      }
      let scheduledAt = Date(timeIntervalSince1970: 1_735_776_000)
      var created: PublicAnnouncementResponse?
      try await app.test(
        .POST, "v1/moderation/announcements",
        beforeRequest: { request async throws in
          request.headers.add(name: "X-Typebar-Moderation-Key", value: "test-announcement-key")
          try request.content.encode(
            AnnouncementPublicationRequest(
              message: "  Service update complete.  ", level: .success, sticky: true,
              scheduledAt: scheduledAt))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          created = try? response.content.decode(PublicAnnouncementResponse.self)
        })
      let announcement = try XCTUnwrap(created)
      XCTAssertEqual(announcement.message, "Service update complete.")
      XCTAssertEqual(announcement.level, .success)
      XCTAssertTrue(announcement.sticky)
      XCTAssertEqual(announcement.scheduledAt, scheduledAt)
      try await app.test(.GET, "v1/announcements") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(
          try? response.content.decode(PublicAnnouncementsResponse.self).announcements,
          [announcement])
      }
      try await app.test(
        .DELETE, "v1/moderation/announcements/\(announcement.id.uuidString)",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Moderation-Key", value: "test-announcement-key")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertTrue((try? response.content.decode(ConnectionRemovalResponse.self).removed) ?? false)
        })
      try await app.test(
        .POST, "v1/moderation/announcements",
        beforeRequest: { request async throws in
          request.headers.add(name: "X-Typebar-Moderation-Key", value: "test-announcement-key")
          try request.content.encode(AnnouncementPublicationRequest(message: "   "))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .badRequest)
        })
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
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
    let afrikaansSubmission = try await store.submitQuote(
      .init(language: "afrikaans", text: "Elke rustige stap maak die volgende taak duideliker.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(afrikaansSubmission.status, "pending")
    let greekSubmission = try await store.submitQuote(
      .init(
        language: "greek", text: "Μια ήρεμη άσκηση κάνει την επόμενη κίνηση πιο καθαρή.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(greekSubmission.status, "pending")
    let greeklishSubmission = try await store.submitQuote(
      .init(
        language: "greeklish", text: "Ena iremo vima kanei tin epomeni kinisi pio ksekathari.",
        attribution: nil), accessToken: session.accessToken)
    XCTAssertEqual(greeklishSubmission.status, "pending")
    let dutchSubmission = try await store.submitQuote(
      .init(language: "dutch", text: "Een rustige oefening maakt de volgende stap helderder.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(dutchSubmission.status, "pending")
    let filipinoSubmission = try await store.submitQuote(
      .init(language: "filipino", text: "Ang payapang hakbang ay nagpapalinaw sa susunod na gawain.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(filipinoSubmission.status, "pending")
    let catalanSubmission = try await store.submitQuote(
      .init(language: "catalan", text: "Un pas tranquil fa més clara la tasca següent.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(catalanSubmission.status, "pending")
    let indonesianSubmission = try await store.submitQuote(
      .init(language: "indonesian", text: "Langkah tenang membuat tugas berikutnya lebih jelas.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(indonesianSubmission.status, "pending")
    let malaySubmission = try await store.submitQuote(
      .init(language: "malay", text: "Langkah tenang menjadikan tugas seterusnya lebih jelas.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(malaySubmission.status, "pending")
    let danishSubmission = try await store.submitQuote(
      .init(language: "danish", text: "En rolig øvelse gør det næste skridt tydeligere.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(danishSubmission.status, "pending")
    let norwegianBokmalSubmission = try await store.submitQuote(
      .init(language: "norwegianBokmal", text: "En rolig øvelse gjør det neste steget tydeligere.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(norwegianBokmalSubmission.status, "pending")
    let norwegianNynorskSubmission = try await store.submitQuote(
      .init(language: "norwegianNynorsk", text: "Eit roleg steg kan gjere den neste oppgåva klårare.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(norwegianNynorskSubmission.status, "pending")
    let swedishSubmission = try await store.submitQuote(
      .init(language: "swedish", text: "En lugn rytm gör nästa rad lättare att hitta.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(swedishSubmission.status, "pending")
    let hungarianSubmission = try await store.submitQuote(
      .init(language: "hungarian", text: "Egy nyugodt gyakorlás tisztábbá teszi a következő lépést.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(hungarianSubmission.status, "pending")
    let czechSubmission = try await store.submitQuote(
      .init(language: "czech", text: "Malý klidný krok může zpřesnit příští úkol.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(czechSubmission.status, "pending")
    let slovakSubmission = try await store.submitQuote(
      .init(language: "slovak", text: "Tichý krok robí ďalšiu úlohu jasnejšou.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(slovakSubmission.status, "pending")
    let slovenianSubmission = try await store.submitQuote(
      .init(language: "slovenian", text: "Mirni korak naredi naslednjo nalogo jasnejšo.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(slovenianSubmission.status, "pending")
    let croatianSubmission = try await store.submitQuote(
      .init(language: "croatian", text: "Mirni korak čini sljedeći zadatak jasnijim.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(croatianSubmission.status, "pending")
    let serbianSubmission = try await store.submitQuote(
      .init(language: "serbian", text: "Миран корак чини следећи задатак јаснијим.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(serbianSubmission.status, "pending")
    let serbianLatinSubmission = try await store.submitQuote(
      .init(language: "serbianLatin", text: "Mirni korak čini sledeći zadatak jasnijim.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(serbianLatinSubmission.status, "pending")
    let bulgarianSubmission = try await store.submitQuote(
      .init(language: "bulgarian", text: "Една спокойна крачка прави следващата задача по-ясна.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(bulgarianSubmission.status, "pending")
    let romanianSubmission = try await store.submitQuote(
      .init(language: "romanian", text: "Un pas liniștit face următoarea sarcină mai clară.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(romanianSubmission.status, "pending")
    let finnishSubmission = try await store.submitQuote(
      .init(language: "finnish", text: "Rauhallinen askel tekee seuraavasta tehtävästä selvemmän.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(finnishSubmission.status, "pending")
    let estonianSubmission = try await store.submitQuote(
      .init(language: "estonian", text: "Rahulik samm teeb järgmise ülesande selgemaks.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(estonianSubmission.status, "pending")
    let icelandicSubmission = try await store.submitQuote(
      .init(language: "icelandic", text: "Rólegt skref gerir næsta verkefni skýrara.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(icelandicSubmission.status, "pending")
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
    let traditionalChineseSubmission = try await store.submitQuote(
      .init(language: "traditionalChinese", text: "安靜的練習能讓下一步慢慢清楚起來。", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(traditionalChineseSubmission.status, "pending")
    let russianSubmission = try await store.submitQuote(
      .init(language: "russian", text: "Спокойная практика делает следующий шаг яснее.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(russianSubmission.status, "pending")
    let ukrainianSubmission = try await store.submitQuote(
      .init(language: "ukrainian", text: "Спокійна практика робить наступний крок яснішим.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(ukrainianSubmission.status, "pending")
    let ukrainianLatinSubmission = try await store.submitQuote(
      .init(language: "ukrainianLatin", text: "Spokiina praktyka robyt nastupnyi krok yasnishym.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(ukrainianLatinSubmission.status, "pending")
    let hiraganaSubmission = try await store.submitQuote(
      .init(language: "japaneseHiragana", text: "しずかなれんしゅうはつぎのいっぽをみえやすくする。", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(hiraganaSubmission.status, "pending")
    let katakanaSubmission = try await store.submitQuote(
      .init(language: "japaneseKatakana", text: "チイサナステップデモツギノページヲアケル。", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(katakanaSubmission.status, "pending")
    let romajiSubmission = try await store.submitQuote(
      .init(language: "japaneseRomaji", text: "Kyou no memo wa ashita no hajime no basho o tsukuru.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(romajiSubmission.status, "pending")
    let koreanSubmission = try await store.submitQuote(
      .init(language: "korean", text: "차분한 연습은 다음에 할 일을 더 또렷하게 만든다.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(koreanSubmission.status, "pending")
    let turkishSubmission = try await store.submitQuote(
      .init(language: "turkish", text: "Sakin bir alıştırma sonraki adımı daha açık gösterir.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(turkishSubmission.status, "pending")
    let polishSubmission = try await store.submitQuote(
      .init(language: "polish", text: "Spokojne ćwiczenie pomaga wyraźniej zobaczyć kolejny krok.", attribution: nil),
      accessToken: session.accessToken)
    XCTAssertEqual(polishSubmission.status, "pending")
    _ = try await store.submitQuote(
      .init(language: "english", text: "A steady habit creates useful momentum.", attribution: nil),
      accessToken: other.accessToken)
    let mine = try await store.quoteSubmissions(accessToken: session.accessToken)
    XCTAssertEqual(
      Set(mine.submissions.map(\.id)),
      Set([
        submitted.id, spanishSubmission.id, germanSubmission.id, afrikaansSubmission.id, greekSubmission.id, greeklishSubmission.id, dutchSubmission.id, filipinoSubmission.id, catalanSubmission.id, indonesianSubmission.id, malaySubmission.id, danishSubmission.id,
        norwegianBokmalSubmission.id, norwegianNynorskSubmission.id, swedishSubmission.id, hungarianSubmission.id, czechSubmission.id, slovakSubmission.id, slovenianSubmission.id, croatianSubmission.id, serbianSubmission.id, serbianLatinSubmission.id, bulgarianSubmission.id, romanianSubmission.id, finnishSubmission.id, estonianSubmission.id, icelandicSubmission.id, frenchSubmission.id,
        italianSubmission.id, portugueseSubmission.id, traditionalChineseSubmission.id,
        russianSubmission.id, ukrainianSubmission.id, ukrainianLatinSubmission.id, hiraganaSubmission.id,
        katakanaSubmission.id, romajiSubmission.id,
        koreanSubmission.id,
        turkishSubmission.id,
        polishSubmission.id,
      ]))
    do {
      try await store.withdrawQuoteSubmission(submitted.id, accessToken: other.accessToken)
      XCTFail("Only the submitting account may withdraw a pending quote")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .profileNotFound) }
    try await store.withdrawQuoteSubmission(submitted.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(spanishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(germanSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(afrikaansSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(greekSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(greeklishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(dutchSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(filipinoSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(catalanSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(indonesianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(malaySubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(danishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(norwegianBokmalSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(norwegianNynorskSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(swedishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(hungarianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(czechSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(slovakSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(slovenianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(croatianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(serbianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(serbianLatinSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(bulgarianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(romanianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(finnishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(estonianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(icelandicSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(frenchSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(italianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(
      portugueseSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(
      traditionalChineseSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(russianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(ukrainianSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(ukrainianLatinSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(hiraganaSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(katakanaSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(romajiSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(koreanSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(turkishSubmission.id, accessToken: session.accessToken)
    try await store.withdrawQuoteSubmission(polishSubmission.id, accessToken: session.accessToken)
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

  func testPasswordAuthenticationRoutesLetProviderUsersAddAndRemovePasswords() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let oauthSession = try await store.registerWithOAuth(
      .init(provider: .github, subject: "password-route-github", email: "provider@example.com"),
      displayName: "Provider User")
    let oauthReauthentication = try await store.beginOAuth(
      provider: .github, purpose: .reauthenticate, accessToken: oauthSession.accessToken)
    _ = try await store.beginOAuthCallback(provider: .github, stateToken: oauthReauthentication.state)
    try await store.completeOAuthCallback(
      stateToken: oauthReauthentication.state,
      identity: .init(provider: .github, subject: "password-route-github", email: "provider@example.com"))
    let oauthCompletion = try await store.oauthCompletion(stateToken: oauthReauthentication.state)
    let oauthReauthenticationToken = try XCTUnwrap(oauthCompletion.reauthenticationToken)

    do {
      try configure(app, authStore: store)
      try await app.test(
        .POST,
        "v1/auth/password/add",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(oauthSession.accessToken)")
          request.headers.add(
            name: "X-Typebar-Reauthentication", value: oauthReauthenticationToken)
          try request.content.encode(
            AddPasswordAuthenticationRequest(newPassword: "a secure password"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let user = try? response.content.decode(AuthUserResponse.self)
          XCTAssertEqual(user?.authenticationMethods, [.password, .github])
        }
      )
      let passwordReauthentication = try await store.reauthenticateWithPassword(
        .init(currentPassword: "a secure password"), accessToken: oauthSession.accessToken)
      try await app.test(
        .DELETE,
        "v1/auth/password",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(oauthSession.accessToken)")
          request.headers.add(
            name: "X-Typebar-Reauthentication", value: passwordReauthentication.reauthenticationToken)
          try request.content.encode(
            RemovePasswordAuthenticationRequest(currentPassword: "a secure password"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let user = try? response.content.decode(AuthUserResponse.self)
          XCTAssertEqual(user?.authenticationMethods, [.github])
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }

    do {
      _ = try await store.login(
        .init(email: "provider@example.com", password: "a secure password"))
      XCTFail("A removed password must no longer be accepted")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }
  }

  func testSessionRevocationRouteRequiresCurrentPasswordAndRevokesEveryDevice() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let firstSession = try await store.register(
      .init(email: "revoke@example.com", password: "a secure password", displayName: "Revoke User"))
    let secondSession = try await store.login(
      .init(email: "revoke@example.com", password: "a secure password"))

    do {
      try configure(app, authStore: store)
      try await app.test(
        .POST,
        "v1/auth/sessions/revoke",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(firstSession.accessToken)")
          try request.content.encode(RevokeSessionsRequest(currentPassword: "a secure password"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertTrue((try? response.content.decode(SessionsRevocationResponse.self))?.revoked ?? false)
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }

    for accessToken in [firstSession.accessToken, secondSession.accessToken] {
      do {
        _ = try await store.authenticatedUser(for: accessToken)
        XCTFail("Session revocation must invalidate every active device")
      } catch let error as AuthStoreError {
        XCTAssertEqual(error, .invalidAccessToken)
      }
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

  func testEmailVerificationIsOneTimeExpiresAndResetsAfterAnEmailChange() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let start = Date(timeIntervalSince1970: 2_000)
    let registration = try await store.register(
      .init(email: "verify@example.com", password: "a secure password", displayName: "Verify User"),
      now: start)
    XCTAssertFalse(registration.user.emailVerified)

    let first = try await store.requestEmailVerification(
      accessToken: registration.accessToken, now: start)
    let second = try await store.requestEmailVerification(
      accessToken: registration.accessToken, now: start.addingTimeInterval(1))
    guard let first, let second else {
      return XCTFail("Unverified accounts must receive verification deliveries")
    }
    XCTAssertNotEqual(first.token, second.token)
    do {
      try await store.completeEmailVerification(.init(token: first.token), now: start.addingTimeInterval(2))
      XCTFail("A newer verification request must revoke the previous token")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidEmailVerificationToken) }
    try await store.completeEmailVerification(.init(token: second.token), now: start.addingTimeInterval(2))
    let verified = try await store.authenticatedUser(for: registration.accessToken, now: start.addingTimeInterval(2))
    XCTAssertTrue(verified.emailVerified)
    let verifiedAccountDelivery = try await store.requestEmailVerification(
      accessToken: registration.accessToken, now: start.addingTimeInterval(3))
    XCTAssertNil(verifiedAccountDelivery)

    let emailChange = try await store.changeEmail(
      .init(currentPassword: "a secure password", newEmail: "verified-new@example.com"),
      accessToken: registration.accessToken,
      now: start.addingTimeInterval(4))
    XCTAssertFalse(emailChange.user.emailVerified)
    let afterChange = try await store.requestEmailVerification(
      accessToken: emailChange.accessToken, now: start.addingTimeInterval(4))
    guard let afterChange else { return XCTFail("Changing an email must require new verification") }
    do {
      try await store.completeEmailVerification(
        .init(token: afterChange.token), now: start.addingTimeInterval(60 * 60 * 24 + 5))
      XCTFail("Expired verification codes must be rejected")
    } catch let error as AuthStoreError { XCTAssertEqual(error, .invalidEmailVerificationToken) }
  }

  func testEmailVerificationRoutesDeliverOnRegistrationAndExposeVerifiedProfileState() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let recorder = EmailVerificationDeliveryRecorder()

    do {
      try configure(
        app,
        authStore: store,
        emailVerificationDelivery: { delivery in await recorder.record(delivery) })
      try await app.test(.GET, "v1/capabilities") { response async in
        let capabilities = try? response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(capabilities?.capabilities["emailVerification"], .available)
      }
      var session: AuthSessionResponse?
      try await app.test(
        .POST,
        "v1/auth/register",
        beforeRequest: { request async throws in
          try request.content.encode(
            RegisterRequest(
              email: "verify-route@example.com", password: "a secure password",
              displayName: "Verify Route"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          session = try? response.content.decode(AuthSessionResponse.self)
          XCTAssertFalse(session?.user.emailVerified ?? true)
        }
      )
      let registrationDeliveryCount = await recorder.count()
      XCTAssertEqual(registrationDeliveryCount, 1)
      guard let session else { return XCTFail("Registration must return a session") }

      try await app.test(
        .POST,
        "v1/auth/email-verification/request",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(try? response.content.decode(EmailVerificationRequestResponse.self), .init(accepted: true))
        }
      )
      let deliveryCount = await recorder.count()
      XCTAssertEqual(deliveryCount, 2)
      guard let delivery = await recorder.latest() else {
        return XCTFail("The delivery handler should receive the newest verification token")
      }
      try await app.test(
        .POST,
        "v1/auth/email-verification/complete",
        beforeRequest: { request async throws in
          try request.content.encode(CompleteEmailVerificationRequest(token: delivery.token))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(try? response.content.decode(EmailVerificationCompletionResponse.self), .init(verified: true))
        }
      )
      try await app.test(
        .GET,
        "v1/profiles/me",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        },
        afterResponse: { response async in
          XCTAssertTrue(try response.content.decode(AuthUserResponse.self).emailVerified)
        }
      )
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
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

  func testPublicProfileDetailsValidateAndControlActivityVisibility() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let now = Date(timeIntervalSince1970: 36_000)
    let session = try await store.register(
      .init(email: "details@example.com", password: "a secure password", displayName: "Details User"),
      now: now)
    let details = ProfileDetails(
      bio: "Building a quiet native typing desk.", keyboard: "Split ANSI QWERTY",
      github: "typebar-user", socialHandle: "typebar", websiteURL: "https://example.com/typebar",
      showActivity: true)
    let updated = try await store.updateProfile(
      .init(profileDetails: details), accessToken: session.accessToken, now: now)
    XCTAssertEqual(updated.profileDetails, details)

    _ = try await store.submitResult(
      result(id: UUID(), wpm: 72, accuracy: 98, finishedAt: now), accessToken: session.accessToken,
      now: now)
    let publicProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(publicProfile.profileDetails, details)
    XCTAssertNotNil(publicProfile.activity)

    let hiddenActivityDetails = ProfileDetails(
      bio: details.bio, keyboard: details.keyboard, github: details.github,
      socialHandle: details.socialHandle, websiteURL: details.websiteURL, showActivity: false)
    _ = try await store.updateProfile(
      .init(profileDetails: hiddenActivityDetails), accessToken: session.accessToken, now: now)
    let hiddenActivityProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(hiddenActivityProfile.profileDetails, hiddenActivityDetails)
    XCTAssertNil(hiddenActivityProfile.activity)

    do {
      _ = try await store.updateProfile(
        .init(profileDetails: .init(websiteURL: "http://example.com")),
        accessToken: session.accessToken, now: now)
      XCTFail("Public profile links must use HTTPS")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidProfileDetails)
    }
    do {
      _ = try await store.updateProfile(
        .init(profileDetails: .init(socialHandle: "this-handle-is-too-long")),
        accessToken: session.accessToken, now: now)
      XCTFail("Social handles must stay within the public profile limit")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidProfileDetails)
    }
    XCTAssertTrue(ProfileReportReason.allCases.contains(.inappropriateBio))
    XCTAssertTrue(ProfileReportReason.allCases.contains(.inappropriateLinks))
  }

  func testPublicProfileStreakUsesUTCDaysAndRespectsActivityVisibility() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let now = Date(timeIntervalSince1970: 345_600)
    let session = try await store.register(
      .init(email: "streak@example.com", password: "a secure password", displayName: "Streak User"),
      now: now)
    for finishedAt in [now, now.addingTimeInterval(-86_400), now.addingTimeInterval(-259_200)] {
      _ = try await store.submitResult(
        result(id: UUID(), wpm: 72, accuracy: 98, finishedAt: finishedAt),
        accessToken: session.accessToken, now: now)
    }

    let visible = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(visible.streak, .init(currentDays: 2, longestDays: 2))

    _ = try await store.updateProfile(
      .init(profileDetails: .init(showActivity: false)), accessToken: session.accessToken, now: now)
    let hidden = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertNil(hidden.activity)
    XCTAssertNil(hidden.streak)
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
    XCTAssertEqual(detailedProfile.startedTestCount, 5)
    XCTAssertEqual(detailedProfile.activity?.testsByDays.last, 4)
    XCTAssertEqual(detailedProfile.totalTypingSeconds, 135)

    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/profiles/\(session.user.id.uuidString)") { response async in
        XCTAssertEqual(response.status, .ok)
        let profile = try? response.content.decode(PublicProfileResponse.self)
        XCTAssertEqual(profile?.displayName, "Profile User")
        XCTAssertEqual(profile?.completedResultCount, 5)
        XCTAssertEqual(profile?.startedTestCount, 5)
        XCTAssertEqual(profile?.totalTypingSeconds, 135)
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

  func testPublicProfileShowsDiscordAvatarOnlyAfterExplicitOptIn() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let now = Date(timeIntervalSince1970: 37_000)
    let avatarHash = "a_" + String(repeating: "a", count: 32)
    let session = try await store.registerWithOAuth(
      .init(
        provider: .discord, subject: "123456789012345678", email: "avatar@example.com",
        avatarHash: avatarHash),
      displayName: "Avatar User", now: now)

    let privateProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertNil(privateProfile.discordAvatar)
    _ = try await store.updateProfile(
      .init(profileDetails: .init(showDiscordAvatar: true)), accessToken: session.accessToken, now: now)
    let visible = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(visible.discordAvatar, .init(subject: "123456789012345678", avatarHash: avatarHash))
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 80, accuracy: 98, finishedAt: now), accessToken: session.accessToken,
      now: now)
    let visibleWPMLeaderboard = try await store.leaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), now: now)
    let visibleExperienceLeaderboard = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(visibleWPMLeaderboard.entries.first?.discordAvatar, visible.discordAvatar)
    XCTAssertEqual(visibleExperienceLeaderboard.entries.first?.discordAvatar, visible.discordAvatar)

    _ = try await store.updateProfile(
      .init(profileDetails: .init(showDiscordAvatar: false)), accessToken: session.accessToken, now: now)
    let hidden = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertNil(hidden.discordAvatar)
    let hiddenWPMLeaderboard = try await store.leaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), now: now)
    let hiddenExperienceLeaderboard = try await store.experienceLeaderboard(now: now)
    XCTAssertNil(hiddenWPMLeaderboard.entries.first?.discordAvatar)
    XCTAssertNil(hiddenExperienceLeaderboard.entries.first?.discordAvatar)

    let invalidAvatar = try await store.registerWithOAuth(
      .init(provider: .discord, subject: "987654321098765432", email: "invalid-avatar@example.com", avatarHash: "../not-an-avatar"),
      displayName: "Safe Avatar", now: now)
    _ = try await store.updateProfile(
      .init(profileDetails: .init(showDiscordAvatar: true)), accessToken: invalidAvatar.accessToken, now: now)
    let invalid = try await store.publicProfile(id: invalidAvatar.user.id, now: now)
    XCTAssertNil(invalid.discordAvatar)
  }

  func testPublicBadgesAreServerDerivedSelectableAndRemovedWithResults() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let now = Date(timeIntervalSince1970: 38_000)
    let session = try await store.register(
      .init(email: "badges@example.com", password: "a secure password", displayName: "Badge User"),
      now: now)
    XCTAssertTrue(session.user.availableBadges.isEmpty)
    XCTAssertNil(session.user.selectedBadgeID)

    do {
      _ = try await store.updateProfile(
        .init(selectedBadgeID: "swift-line"), accessToken: session.accessToken, now: now)
      XCTFail("Users cannot select a badge that has not been earned from server results")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidProfileDetails)
    }

    _ = try await store.submitResult(
      result(id: UUID(), wpm: 80, accuracy: 98, durationSeconds: 15 * 60, finishedAt: now),
      accessToken: session.accessToken, now: now)
    let earned = try await store.authenticatedUser(for: session.accessToken, now: now)
    XCTAssertEqual(
      earned.availableBadges.map(\.id), ["first-finish", "clear-key", "swift-line", "steady-room"])
    XCTAssertNil(earned.selectedBadgeID)

    let selected = try await store.updateProfile(
      .init(selectedBadgeID: "swift-line"), accessToken: session.accessToken, now: now)
    XCTAssertEqual(selected.selectedBadgeID, "swift-line")
    let selectedPublicProfile = try await store.publicProfile(id: session.user.id, now: now)
    let wpmLeaderboard = try await store.leaderboard(
      .init(mode: nil, language: nil, period: "all", limit: 25), now: now)
    let experienceLeaderboard = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(selectedPublicProfile.selectedBadge?.id, "swift-line")
    XCTAssertEqual(wpmLeaderboard.entries.first?.selectedBadge?.id, "swift-line")
    XCTAssertEqual(experienceLeaderboard.entries.first?.selectedBadge?.id, "swift-line")

    let legacyProfileUpdate = try JSONDecoder().decode(
      UpdateProfileRequest.self,
      from: Data(#"{"displayName":"Badge User Updated"}"#.utf8))
    let preserved = try await store.updateProfile(
      legacyProfileUpdate, accessToken: session.accessToken, now: now)
    XCTAssertEqual(preserved.selectedBadgeID, "swift-line")

    let hidden = try await store.updateProfile(
      .init(selectedBadgeID: ""), accessToken: session.accessToken, now: now)
    XCTAssertNil(hidden.selectedBadgeID)
    let hiddenPublicProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertNil(hiddenPublicProfile.selectedBadge)

    _ = try await store.updateProfile(
      .init(selectedBadgeID: "steady-room"), accessToken: session.accessToken, now: now)
    _ = try await store.deleteResults(
      .init(currentPassword: "a secure password"), accessToken: session.accessToken, now: now)
    let afterDeletion = try await store.authenticatedUser(for: session.accessToken, now: now)
    let deletedPublicProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertTrue(afterDeletion.availableBadges.isEmpty)
    XCTAssertNil(afterDeletion.selectedBadgeID)
    XCTAssertNil(deletedPublicProfile.selectedBadge)
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
    let aliceRank = try await store.friendLeaderboardRank(
      .init(mode: nil, language: nil, period: "all", limit: 1), accessToken: alice.accessToken,
      now: now)
    XCTAssertEqual(aliceRank.entry?.userID, alice.user.id)
    XCTAssertEqual(aliceRank.entry?.rank, 2)
  }

  func testFriendLeaderboardRouteRequiresAuthentication() async throws {
    let app = try await Application.make(.testing)
    do {
      try configureTestApp(app)
      try await app.test(.GET, "v1/leaderboards/friends") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.GET, "v1/leaderboards/rank") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.GET, "v1/leaderboards/experience/rank") { response async in
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
    let globalXPEntries = try await store.experienceLeaderboard(now: now).entries
    let friendXPEntries = try await store.friendExperienceLeaderboard(
      accessToken: bob.accessToken, now: now).entries
    let hiddenWPMRank = try await store.leaderboardRank(
      .init(mode: nil, language: nil, period: "all", limit: 1), accessToken: alice.accessToken,
      now: now)
    let hiddenXPRank = try await store.experienceLeaderboardRank(
      accessToken: alice.accessToken, now: now)
    XCTAssertEqual(globalEntries.map(\.userID), [bob.user.id])
    XCTAssertEqual(friendEntries.map(\.userID), [bob.user.id])
    XCTAssertTrue(globalXPEntries.allSatisfy { $0.userID != alice.user.id })
    XCTAssertTrue(friendXPEntries.allSatisfy { $0.userID != alice.user.id })
    XCTAssertNil(hiddenWPMRank.entry)
    XCTAssertNil(hiddenXPRank.entry)

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
      .init(mode: "time", language: "english", period: "all", limit: 1))
    let fasterRank = try await store.leaderboardRank(
      .init(mode: "time", language: "english", period: "all", limit: 1),
      accessToken: faster.accessToken)
    let slowerRank = try await store.leaderboardRank(
      .init(mode: "time", language: "english", period: "all", limit: 1),
      accessToken: slower.accessToken)
    XCTAssertEqual(response.entries.map(\.displayName), ["Faster"])
    XCTAssertEqual(fasterRank.entry?.rank, 1)
    XCTAssertEqual(slowerRank.entry?.rank, 2)
    let fullResponse = try await store.leaderboard(
      .init(mode: "time", language: "english", period: "all", limit: 10))
    XCTAssertEqual(fullResponse.entries.map(\.displayName), ["Faster", "Slower"])
    XCTAssertEqual(fullResponse.entries.map(\.rank), [1, 2])
    XCTAssertEqual(fullResponse.entries.map(\.wpm), [101, 80])
    XCTAssertEqual(fullResponse.entries.map(\.consistency), [94, 77])
    XCTAssertEqual(fullResponse.entries.map(\.id).count, Set(fullResponse.entries.map(\.id)).count)
  }

  func testResultSubmissionDefaultsMissingConsistencyForLegacyClient() throws {
    let id = UUID()
    let payload = """
      {"id":"\(id.uuidString)","mode":"time","language":"english","durationSeconds":30,"wpm":80,"rawWpm":80,"accuracy":100,"errorCount":0,"eventCount":200,"startedAt":1000,"finishedAt":1030}
      """

    let request = try JSONDecoder().decode(ResultSubmissionRequest.self, from: Data(payload.utf8))

    XCTAssertEqual(request.consistency, 0)
    XCTAssertEqual(request.restartCount, 0)
  }

  func testSubmittedResultsTrackRestartCountsWithoutDoubleCountingRetries() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "restart-count@example.com", password: "a secure password", displayName: "Restart Count"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let firstID = UUID()

    _ = try await store.submitResult(
      result(id: firstID, wpm: 72, accuracy: 98, restartCount: 2, finishedAt: now),
      accessToken: session.accessToken, now: now)
    _ = try await store.submitResult(
      result(id: firstID, wpm: 72, accuracy: 98, restartCount: 2, finishedAt: now),
      accessToken: session.accessToken, now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 74, accuracy: 99, finishedAt: now),
      accessToken: session.accessToken, now: now)

    let profile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(profile.completedResultCount, 2)
    XCTAssertEqual(profile.startedTestCount, 4)

    _ = try await store.deleteResults(
      .init(currentPassword: "a secure password"), accessToken: session.accessToken, now: now)
    let clearedProfile = try await store.publicProfile(id: session.user.id, now: now)
    XCTAssertEqual(clearedProfile.completedResultCount, 0)
    XCTAssertEqual(clearedProfile.startedTestCount, 0)
  }

  func testDeveloperAccessKeysAreScopedHashedAndCanBeRevoked() async throws {
    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("typebar-developer-key-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let store = try AuthStore(fileURL: fileURL, bcryptCost: 4)
    let owner = try await store.register(
      .init(email: "key-owner@example.com", password: "a secure password", displayName: "Key Owner"))
    let other = try await store.register(
      .init(email: "key-other@example.com", password: "a secure password", displayName: "Key Other"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let created = try await store.createDeveloperAccessKey(
      .init(name: "results-uploader"), accessToken: owner.accessToken, now: now)

    XCTAssertTrue(created.accessKey.hasPrefix("tbak_"))
    XCTAssertEqual(created.key.name, "results-uploader")
    XCTAssertTrue(created.key.enabled)
    XCTAssertNil(created.key.lastUsedAt)
    XCTAssertFalse(try String(contentsOf: fileURL).contains(created.accessKey))
    let ownerKeys = try await store.developerAccessKeys(accessToken: owner.accessToken, now: now).keys
    let otherKeys = try await store.developerAccessKeys(accessToken: other.accessToken, now: now).keys
    XCTAssertEqual(ownerKeys, [created.key])
    XCTAssertTrue(otherKeys.isEmpty)

    _ = try await store.submitResult(
      result(id: UUID(), wpm: 80, accuracy: 100, finishedAt: now),
      credential: .developerAccessKey(created.accessKey), now: now)
    let used = try await store.developerAccessKeys(accessToken: owner.accessToken, now: now).keys
    XCTAssertEqual(used.first?.lastUsedAt, now)

    let renamed = try await store.updateDeveloperAccessKey(
      id: created.key.id, request: .init(name: "ci_uploader", enabled: false),
      accessToken: owner.accessToken, now: now.addingTimeInterval(1))
    XCTAssertEqual(renamed.name, "ci_uploader")
    XCTAssertFalse(renamed.enabled)
    XCTAssertEqual(renamed.lastUsedAt, now)
    do {
      _ = try await store.submitResult(
        result(id: UUID(), wpm: 80, accuracy: 100, finishedAt: now),
        credential: .developerAccessKey(created.accessKey), now: now)
      XCTFail("Disabled developer keys must not upload results")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .inactiveDeveloperAccessKey)
    }
    do {
      _ = try await store.updateDeveloperAccessKey(
        id: created.key.id, request: .init(name: "taken", enabled: nil),
        accessToken: other.accessToken, now: now)
      XCTFail("A developer key must not be manageable from another account")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .developerAccessKeyNotFound)
    }
    try await store.deleteDeveloperAccessKey(id: created.key.id, accessToken: owner.accessToken, now: now)
    do {
      _ = try await store.submitResult(
        result(id: UUID(), wpm: 80, accuracy: 100, finishedAt: now),
        credential: .developerAccessKey(created.accessKey), now: now)
      XCTFail("Deleted developer keys must not upload results")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidDeveloperAccessKey)
    }
  }

  func testDeveloperAccessKeyNamesAndLimitsAreValidated() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "key-limit@example.com", password: "a secure password", displayName: "Key Limit"))
    do {
      _ = try await store.createDeveloperAccessKey(.init(name: "not allowed"), accessToken: session.accessToken)
      XCTFail("Developer key names must be slug-like")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidDeveloperAccessKeyName)
    }
    for number in 1...5 {
      _ = try await store.createDeveloperAccessKey(
        .init(name: "key-\(number)"), accessToken: session.accessToken)
    }
    do {
      _ = try await store.createDeveloperAccessKey(.init(name: "one-more"), accessToken: session.accessToken)
      XCTFail("An account must not create more than five developer keys")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .developerAccessKeyLimitReached)
    }
  }

  func testAccountResultHistoryIsPrivatePagedAndAvailableToDeveloperKeys() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(
      .init(email: "history-owner@example.com", password: "a secure password", displayName: "History Owner"))
    let other = try await store.register(
      .init(email: "history-other@example.com", password: "a secure password", displayName: "History Other"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let key = try await store.createDeveloperAccessKey(
      .init(name: "result-reader"), accessToken: owner.accessToken, now: now)
    let oldID = UUID()
    let recentID = UUID()
    let otherID = UUID()
    _ = try await store.submitResult(
      result(id: oldID, wpm: 70, accuracy: 100, finishedAt: now.addingTimeInterval(-120)),
      accessToken: owner.accessToken, now: now)
    _ = try await store.submitResult(
      result(id: recentID, wpm: 90, accuracy: 100, finishedAt: now.addingTimeInterval(-30)),
      credential: .developerAccessKey(key.accessKey), now: now)
    _ = try await store.submitResult(
      result(id: otherID, wpm: 110, accuracy: 100, finishedAt: now.addingTimeInterval(-10)),
      accessToken: other.accessToken, now: now)
    let tagged = try await store.updateResultTags(
      id: recentID, request: .init(tags: ["review", "café"]), accessToken: owner.accessToken,
      now: now)

    let firstPage = try await store.results(
      .init(offset: 0, limit: 1), credential: .developerAccessKey(key.accessKey), now: now)
    XCTAssertEqual(firstPage.total, 2)
    XCTAssertEqual(firstPage.results.map(\.id), [recentID])
    XCTAssertEqual(tagged.tags, ["review", "café"])
    XCTAssertEqual(firstPage.results.first?.tags, ["review", "café"])
    let secondPage = try await store.results(
      .init(offset: 1, limit: 1), credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(secondPage.results.map(\.id), [oldID])
    let filtered = try await store.results(
      .init(finishedOnOrAfter: now.addingTimeInterval(-60).timeIntervalSince1970),
      credential: .accessToken(owner.accessToken), now: now)
    XCTAssertEqual(filtered.results.map(\.id), [recentID])
    let detail = try await store.result(
      id: recentID, credential: .developerAccessKey(key.accessKey), now: now)
    let usedKey = try await store.developerAccessKeys(accessToken: owner.accessToken, now: now).keys.first
    XCTAssertEqual(detail.id, recentID)
    XCTAssertEqual(usedKey?.lastUsedAt, now)

    do {
      _ = try await store.result(id: otherID, credential: .accessToken(owner.accessToken), now: now)
      XCTFail("An account must not read another account's submitted result")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .resultNotFound)
    }
    do {
      _ = try await store.updateResultTags(
        id: otherID, request: .init(tags: ["private"]), accessToken: owner.accessToken, now: now)
      XCTFail("An account must not modify another account's result tags")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .resultNotFound)
    }
    do {
      _ = try await store.updateResultTags(
        id: recentID, request: .init(tags: ["duplicate", "DUPLICATE"]),
        accessToken: owner.accessToken, now: now)
      XCTFail("Duplicate result tags must be rejected")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidResultTags)
    }
    do {
      _ = try await store.results(
        .init(offset: -1, limit: 1), credential: .accessToken(owner.accessToken), now: now)
      XCTFail("Negative result pagination offsets must be rejected")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidResultQuery)
    }
  }

  func testDeletingResultsRequiresConfirmationAndPreservesOtherAccounts() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let owner = try await store.register(
      .init(email: "clear-owner@example.com", password: "a secure password", displayName: "Clear Owner"))
    let other = try await store.register(
      .init(email: "clear-other@example.com", password: "a secure password", displayName: "Clear Other"))
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 80, accuracy: 100, finishedAt: now), accessToken: owner.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 90, accuracy: 100, finishedAt: now), accessToken: owner.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 100, accuracy: 100, finishedAt: now), accessToken: other.accessToken,
      now: now)

    do {
      _ = try await store.deleteResults(.init(currentPassword: nil), accessToken: owner.accessToken, now: now)
      XCTFail("Deleting remote results must require a fresh account confirmation")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidReauthenticationToken)
    }
    do {
      _ = try await store.deleteResults(
        .init(currentPassword: "wrong password"), accessToken: owner.accessToken, now: now)
      XCTFail("Deleting remote results must reject an incorrect password")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }

    let deletion = try await store.deleteResults(
      .init(currentPassword: "a secure password"), accessToken: owner.accessToken, now: now)
    let ownerResults = try await store.results(
      .init(), credential: .accessToken(owner.accessToken), now: now)
    let otherResults = try await store.results(
      .init(), credential: .accessToken(other.accessToken), now: now)
    let currentOwner = try await store.authenticatedUser(for: owner.accessToken, now: now)
    XCTAssertTrue(deletion.deleted)
    XCTAssertEqual(deletion.removedCount, 2)
    XCTAssertTrue(ownerResults.results.isEmpty)
    XCTAssertEqual(otherResults.results.count, 1)
    XCTAssertEqual(currentOwner.id, owner.user.id)
  }

  func testOAuthIdentitiesSupportPasswordlessLoginLinkingAndSafeUnlinking() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let github = OAuthProviderIdentity(
      provider: .github, subject: "github-user-42", email: "github@example.com")
    let oauthSession = try await store.registerWithOAuth(
      github, displayName: "GitHub User")

    XCTAssertTrue(oauthSession.user.emailVerified)
    XCTAssertEqual(oauthSession.user.authenticationMethods, [.github])
    do {
      _ = try await store.login(
        .init(email: "github@example.com", password: "a secure password"))
      XCTFail("Passwordless accounts must reject password sign-in")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidCredentials)
    }

    let secondOAuthSession = try await store.loginWithOAuth(github)
    XCTAssertEqual(secondOAuthSession.user.id, oauthSession.user.id)
    XCTAssertNotEqual(secondOAuthSession.accessToken, oauthSession.accessToken)

    let githubReauthentication = try await store.beginOAuth(
      provider: .github, purpose: .reauthenticate, accessToken: oauthSession.accessToken)
    _ = try await store.beginOAuthCallback(provider: .github, stateToken: githubReauthentication.state)
    try await store.completeOAuthCallback(stateToken: githubReauthentication.state, identity: github)
    let githubCompletion = try await store.oauthCompletion(stateToken: githubReauthentication.state)
    let githubReauthenticationToken = try XCTUnwrap(githubCompletion.reauthenticationToken)
    do {
      _ = try await store.unlinkOAuth(
        .github, accessToken: oauthSession.accessToken,
        reauthenticationToken: githubReauthenticationToken)
      XCTFail("The final authentication method must remain linked")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .cannotRemoveLastAuthentication)
    }

    let google = OAuthProviderIdentity(
      provider: .google, subject: "google-user-21", email: "google@example.com")
    let linkedUser = try await store.linkOAuth(google, accessToken: oauthSession.accessToken)
    XCTAssertEqual(linkedUser.authenticationMethods, [.github, .google])

    let discord = OAuthProviderIdentity(
      provider: .discord, subject: "discord-user-7", email: "discord@example.com")
    let linkedDiscordUser = try await store.linkOAuth(discord, accessToken: oauthSession.accessToken)
    XCTAssertEqual(linkedDiscordUser.authenticationMethods, [.github, .google, .discord])
    let discordLogin = try await store.loginWithOAuth(discord)
    XCTAssertEqual(discordLogin.user.id, oauthSession.user.id)

    let googleReauthentication = try await store.beginOAuth(
      provider: .google, purpose: .reauthenticate, accessToken: oauthSession.accessToken)
    _ = try await store.beginOAuthCallback(provider: .google, stateToken: googleReauthentication.state)
    try await store.completeOAuthCallback(stateToken: googleReauthentication.state, identity: google)
    let googleCompletion = try await store.oauthCompletion(stateToken: googleReauthentication.state)
    let googleReauthenticationToken = try XCTUnwrap(googleCompletion.reauthenticationToken)
    let remainingGoogleUser = try await store.unlinkOAuth(
      .github, accessToken: oauthSession.accessToken, reauthenticationToken: googleReauthenticationToken)
    XCTAssertEqual(remainingGoogleUser.authenticationMethods, [.google, .discord])
    let googleLogin = try await store.loginWithOAuth(google)
    XCTAssertEqual(googleLogin.user.id, oauthSession.user.id)

    let passwordSession = try await store.register(
      .init(email: "password@example.com", password: "a secure password", displayName: "Password User"))
    do {
      _ = try await store.linkOAuth(google, accessToken: passwordSession.accessToken)
      XCTFail("A provider identity must not move to another account")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .oauthIdentityAlreadyLinked)
    }

    let passwordGitHub = OAuthProviderIdentity(
      provider: .github, subject: "github-user-84", email: "second-github@example.com")
    let linkedPasswordUser = try await store.linkOAuth(
      passwordGitHub, accessToken: passwordSession.accessToken)
    XCTAssertEqual(linkedPasswordUser.authenticationMethods, [.password, .github])
    let passwordReauthentication = try await store.reauthenticateWithPassword(
      .init(currentPassword: "a secure password"), accessToken: passwordSession.accessToken)
    let passwordOnlyUser = try await store.unlinkOAuth(
      .github, accessToken: passwordSession.accessToken,
      reauthenticationToken: passwordReauthentication.reauthenticationToken)
    XCTAssertEqual(passwordOnlyUser.authenticationMethods, [.password])
  }

  func testReauthenticationCredentialsExpireAndCannotBeReplayed() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let now = Date(timeIntervalSince1970: 24_000)
    let github = OAuthProviderIdentity(
      provider: .github, subject: "reauthentication-user", email: "reauthentication@example.com")
    let session = try await store.registerWithOAuth(github, displayName: "Reauthentication User", now: now)

    let authorization = try await store.beginOAuth(
      provider: .github, purpose: .reauthenticate, accessToken: session.accessToken, now: now)
    _ = try await store.beginOAuthCallback(
      provider: .github, stateToken: authorization.state, now: now)
    try await store.completeOAuthCallback(
      stateToken: authorization.state, identity: github, now: now)
    let completion = try await store.oauthCompletion(stateToken: authorization.state, now: now)
    let oauthToken = try XCTUnwrap(completion.reauthenticationToken)

    let user = try await store.addPasswordAuthentication(
      .init(newPassword: "a secure password"), accessToken: session.accessToken,
      reauthenticationToken: oauthToken, now: now)
    XCTAssertEqual(user.authenticationMethods, [.password, .github])
    do {
      _ = try await store.addPasswordAuthentication(
        .init(newPassword: "another secure password"), accessToken: session.accessToken,
        reauthenticationToken: oauthToken, now: now)
      XCTFail("A reauthentication credential must be one-time")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidReauthenticationToken)
    }

    let passwordReauthentication = try await store.reauthenticateWithPassword(
      .init(currentPassword: "a secure password"), accessToken: session.accessToken, now: now)
    do {
      try await store.revokeAllSessions(
        .init(currentPassword: nil), accessToken: session.accessToken,
        reauthenticationToken: passwordReauthentication.reauthenticationToken,
        now: now.addingTimeInterval(5 * 60 + 1))
      XCTFail("A reauthentication credential must expire after five minutes")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidReauthenticationToken)
    }
  }

  func testOAuthTransactionsAreOneTimeAndCompleteRegistrationOrLinking() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let start = Date(timeIntervalSince1970: 12_000)
    let signIn = try await store.beginOAuth(provider: .google, purpose: .signIn, now: start)
    XCTAssertEqual(signIn.state.count, 43)
    XCTAssertEqual(signIn.codeChallenge.count, 43)

    let callback = try await store.beginOAuthCallback(
      provider: .google, stateToken: signIn.state, now: start)
    XCTAssertEqual(callback.provider, .google)
    XCTAssertEqual(callback.codeVerifier.count, 43)
    do {
      _ = try await store.beginOAuthCallback(provider: .google, stateToken: signIn.state, now: start)
      XCTFail("OAuth callback state must not be replayed")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidOAuthTransaction)
    }

    try await store.completeOAuthCallback(
      stateToken: signIn.state,
      identity: .init(
        provider: .google, subject: "google-subject-1", email: "google-flow@example.com",
        suggestedDisplayName: "Google Flow"),
      now: start)
    let registration = try await store.oauthCompletion(stateToken: signIn.state, now: start)
    XCTAssertEqual(registration.status, .registrationRequired)
    XCTAssertEqual(registration.email, "google-flow@example.com")
    XCTAssertEqual(registration.suggestedDisplayName, "Google Flow")

    let oauthSession = try await store.completeOAuthRegistration(
      stateToken: signIn.state, displayName: "Native Google", now: start)
    XCTAssertEqual(oauthSession.user.authenticationMethods, [.google])
    do {
      _ = try await store.oauthCompletion(stateToken: signIn.state, now: start)
      XCTFail("Completed OAuth transactions must be consumed")
    } catch let error as AuthStoreError {
      XCTAssertEqual(error, .invalidOAuthTransaction)
    }

    let link = try await store.beginOAuth(
      provider: .github, purpose: .link, accessToken: oauthSession.accessToken, now: start)
    _ = try await store.beginOAuthCallback(provider: .github, stateToken: link.state, now: start)
    try await store.completeOAuthCallback(
      stateToken: link.state,
      identity: .init(provider: .github, subject: "github-subject-2", email: "github-flow@example.com"),
      now: start)
    let linked = try await store.oauthCompletion(stateToken: link.state, now: start)
    XCTAssertEqual(linked.status, .linked)
    XCTAssertEqual(linked.user?.authenticationMethods, [.github, .google])
  }

  func testOAuthProviderAuthorizationURLsUseMinimalScopesAndPKCE() throws {
    let githubRedirect = try XCTUnwrap(
      URL(string: "https://typebar.example.com/v1/auth/oauth/github/callback"))
    let googleRedirect = try XCTUnwrap(
      URL(string: "https://typebar.example.com/v1/auth/oauth/google/callback"))
    let discordRedirect = try XCTUnwrap(
      URL(string: "https://typebar.example.com/v1/auth/oauth/discord/callback"))
    let client = OAuthProviderClient(configurations: [
      .github: try .init(clientID: "github-client", clientSecret: "github-secret", redirectURL: githubRedirect),
      .google: try .init(clientID: "google-client", clientSecret: "google-secret", redirectURL: googleRedirect),
      .discord: try .init(clientID: "discord-client", clientSecret: "discord-secret", redirectURL: discordRedirect),
    ])
    let request = OAuthAuthorizationRequest(
      provider: .github, state: "state-token", codeChallenge: "challenge-token")
    let githubURL = try client.authorizationURL(for: request)
    let githubQuery = Dictionary(
      uniqueKeysWithValues: (URLComponents(url: githubURL, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .compactMap { item in item.value.map { (item.name, $0) } })
    XCTAssertEqual(githubURL.host, "github.com")
    XCTAssertEqual(githubQuery["scope"], "read:user user:email")
    XCTAssertEqual(githubQuery["state"], "state-token")
    XCTAssertEqual(githubQuery["code_challenge"], "challenge-token")
    XCTAssertEqual(githubQuery["code_challenge_method"], "S256")

    let googleURL = try client.authorizationURL(for: .init(
      provider: .google, state: "google-state", codeChallenge: "google-challenge"))
    let googleQuery = Dictionary(
      uniqueKeysWithValues: (URLComponents(url: googleURL, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .compactMap { item in item.value.map { (item.name, $0) } })
    XCTAssertEqual(googleURL.host, "accounts.google.com")
    XCTAssertEqual(googleQuery["scope"], "openid profile email")
    XCTAssertEqual(googleQuery["prompt"], "select_account")
    XCTAssertEqual(googleQuery["redirect_uri"], googleRedirect.absoluteString)

    let discordURL = try client.authorizationURL(for: .init(
      provider: .discord, state: "discord-state", codeChallenge: "discord-challenge"))
    let discordQuery = Dictionary(
      uniqueKeysWithValues: (URLComponents(url: discordURL, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .compactMap { item in item.value.map { (item.name, $0) } })
    XCTAssertEqual(discordURL.host, "discord.com")
    XCTAssertEqual(discordURL.path, "/oauth2/authorize")
    XCTAssertEqual(discordQuery["scope"], "identify email")
    XCTAssertEqual(discordQuery["state"], "discord-state")
    XCTAssertEqual(discordQuery["code_challenge_method"], "S256")
  }

  func testOAuthRoutesUseInjectedIdentityAndReturnToTheNativeCallback() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let redirectURL = try XCTUnwrap(
      URL(string: "https://typebar.example.com/v1/auth/oauth/discord/callback"))
    let oauthClient = OAuthProviderClient(
      configurations: [
        .discord: try .init(clientID: "discord-client", clientSecret: "discord-secret", redirectURL: redirectURL)
      ],
      identityResolver: { provider, _, _ in
        guard provider == .discord else { throw OAuthProviderClientError.providerRejected }
        return .init(
          provider: .discord, subject: "route-discord-subject", email: "route-discord@example.com",
          suggestedDisplayName: "Route Discord")
      })
    do {
      try configure(app, authStore: store, oauthProviderClient: oauthClient)
      try await app.test(.GET, "v1/capabilities") { response async in
        let capabilities = try? response.content.decode(ServiceCapabilitiesResponse.self)
        XCTAssertEqual(capabilities?.capabilities["discordOAuth"], .available)
        XCTAssertEqual(capabilities?.capabilities["githubOAuth"], .planned)
      }
      try await app.test(.POST, "v1/auth/oauth/discord/start", beforeRequest: { request in
        try request.content.encode(OAuthStartRequest(purpose: .signIn))
      }) { response async in
        XCTAssertEqual(response.status, .ok)
        let started = try? response.content.decode(OAuthStartResponse.self)
        XCTAssertEqual(URL(string: started?.authorizationURL ?? "")?.host, "discord.com")
      }

      let transaction = try await store.beginOAuth(provider: .discord, purpose: .signIn)
      try await app.test(
        .GET, "v1/auth/oauth/discord/callback?code=test-code&state=\(transaction.state)"
      ) { response async in
        XCTAssertEqual(response.status, .found)
        let callbackURL = response.headers.first(name: "Location")
        XCTAssertEqual(URL(string: callbackURL ?? "")?.scheme, "typebar")
        XCTAssertEqual(URLComponents(string: callbackURL ?? "")?.queryItems?.first(where: { $0.name == "state" })?.value, transaction.state)
      }
      try await app.test(.GET, "v1/auth/oauth/completion?state=\(transaction.state)") { response async in
        XCTAssertEqual(response.status, .ok)
        let completion = try? response.content.decode(OAuthCompletionResponse.self)
        XCTAssertEqual(completion?.status, .registrationRequired)
        XCTAssertEqual(completion?.email, "route-discord@example.com")
      }
      try await app.test(.POST, "v1/auth/oauth/registration", beforeRequest: { request in
        try request.content.encode(
          OAuthRegistrationRequest(state: transaction.state, displayName: "Native Route"))
      }) { response async in
        XCTAssertEqual(response.status, .ok)
        let session = try? response.content.decode(AuthSessionResponse.self)
        XCTAssertEqual(session?.user.authenticationMethods, [.discord])
        XCTAssertTrue(session?.user.emailVerified ?? false)
      }
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
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
    let weekly = try await store.experienceLeaderboard(now: now)
    XCTAssertEqual(weekly.entries.map(\.displayName), ["XP Alice", "XP Bob"])
    XCTAssertEqual(
      weekly.entries.map(\.totalExperience),
      [aliceResponse.totalExperience, TypebarExperiencePolicy.points(for: bobRequest)])
    let bobRank = try await store.experienceLeaderboardRank(accessToken: bob.accessToken, now: now)
    XCTAssertEqual(bobRank.entry?.rank, 2)

    let zen = ResultSubmissionRequest(
      id: UUID(), mode: "zen", language: "english", durationSeconds: nil, wordLimit: nil, wpm: 80,
      rawWpm: 80, accuracy: 100, errorCount: 0, eventCount: 60,
      startedAt: now.addingTimeInterval(-9), finishedAt: now)
    XCTAssertEqual(TypebarExperiencePolicy.points(for: zen), 0)
  }

  func testExperienceLeaderboardSeparatesCurrentAndPreviousISOWeeks() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let current = try await store.register(
      .init(email: "xp-current@example.com", password: "a secure password", displayName: "Current XP"))
    let previous = try await store.register(
      .init(email: "xp-previous@example.com", password: "a secure password", displayName: "Previous XP"))
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z"))
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 70, accuracy: 99, finishedAt: now), accessToken: current.accessToken,
      now: now)
    _ = try await store.submitResult(
      result(id: UUID(), wpm: 75, accuracy: 99, finishedAt: now.addingTimeInterval(-60 * 60 * 24 * 8)),
      accessToken: previous.accessToken, now: now)

    let thisWeek = try await store.experienceLeaderboard(period: "week", now: now)
    let lastWeek = try await store.experienceLeaderboard(period: "lastWeek", now: now)
    let previousRank = try await store.experienceLeaderboardRank(
      period: "lastWeek", accessToken: previous.accessToken, now: now)

    XCTAssertEqual(thisWeek.period, "week")
    XCTAssertEqual(thisWeek.entries.map(\.userID), [current.user.id])
    XCTAssertEqual(lastWeek.period, "lastWeek")
    XCTAssertEqual(lastWeek.entries.map(\.userID), [previous.user.id])
    XCTAssertEqual(previousRank.period, "lastWeek")
    XCTAssertEqual(previousRank.entry?.rank, 1)

    do {
      _ = try await store.experienceLeaderboard(period: "month", now: now)
      XCTFail("Unknown experience leaderboard period must be rejected")
    } catch let error as ResultStoreError {
      XCTAssertEqual(error, .invalidResult)
    }
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

    for (offset, language) in [
      "traditionalChinese", "afrikaans", "greek", "greeklish", "dutch", "filipino", "catalan", "indonesian", "malay", "danish", "norwegianBokmal", "norwegianNynorsk", "swedish", "hungarian", "czech", "slovak", "slovenian", "croatian", "serbian", "serbianLatin", "bulgarian", "romanian", "finnish", "estonian", "icelandic", "russian",
      "ukrainian", "ukrainianLatin", "japaneseHiragana", "japaneseKatakana", "japaneseRomaji", "korean",
      "turkish", "polish",
    ].enumerated() {
      let accepted = try await store.submitResult(
        result(
          id: UUID(), wpm: 81 + offset, accuracy: 100, language: language,
          finishedAt: now.addingTimeInterval(Double(offset + 1))),
        accessToken: session.accessToken, now: now)
      XCTAssertTrue(accepted.leaderboardEligible)
      let leaderboard = try await store.leaderboard(
        .init(mode: "time", language: language, period: "all", limit: 10), now: now)
      XCTAssertEqual(leaderboard.entries.map(\.wpm), [81 + offset])
    }
  }

  func testResultRoutesRequireAuthenticationAndReturnLeaderboard() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "me@example.com", password: "a secure password", displayName: "Route User"))
    let now = Date.now
    let resultID = UUID()

    do {
      try configure(app, authStore: store)
      try await app.test(.POST, "v1/results") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(.DELETE, "v1/results") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .POST, "v1/results",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(result(id: resultID, wpm: 88, accuracy: 99, finishedAt: now))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertTrue(
            (try? response.content.decode(ResultSubmissionResponse.self))?.leaderboardEligible
              ?? false)
        })
      try await app.test(
        .PATCH, "v1/results/\(resultID.uuidString)/tags",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(UpdateResultTagsRequest(tags: ["route"]))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual((try? response.content.decode(AccountResultResponse.self))?.tags, ["route"])
        })
      try await app.test(.GET, "v1/leaderboards?mode=time&language=english") { response async in
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(
          (try? response.content.decode(LeaderboardResponse.self))?.entries.first?.displayName,
          "Route User")
      }
      try await app.test(
        .GET, "v1/leaderboards/rank?mode=time&language=english",
        beforeRequest: { request async in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(
            (try? response.content.decode(LeaderboardRankResponse.self))?.entry?.displayName,
            "Route User")
        })
      try await app.test(.GET, "v1/leaderboards/experience") { response async in
        XCTAssertEqual(response.status, .ok)
        let leaderboard = try? response.content.decode(ExperienceLeaderboardResponse.self)
        let entries = leaderboard?.entries
        XCTAssertEqual(leaderboard?.period, "week")
        XCTAssertEqual(entries?.first?.displayName, "Route User")
        XCTAssertTrue((entries?.first?.totalExperience ?? 0) > 0)
      }
      try await app.test(.GET, "v1/leaderboards/experience?period=lastWeek") { response async in
        XCTAssertEqual(response.status, .ok)
        let leaderboard = try? response.content.decode(ExperienceLeaderboardResponse.self)
        XCTAssertEqual(leaderboard?.period, "lastWeek")
        XCTAssertTrue(leaderboard?.entries.isEmpty ?? false)
      }
      try await app.test(.GET, "v1/leaderboards/experience?period=month") { response async in
        XCTAssertEqual(response.status, .badRequest)
      }
      try await app.test(
        .GET, "v1/leaderboards/experience/rank",
        beforeRequest: { request async in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual(
            (try? response.content.decode(ExperienceLeaderboardRankResponse.self))?.entry?.displayName,
            "Route User")
        })
      try await app.test(.GET, "v1/leaderboards/experience/friends") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .DELETE, "v1/results",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(DeleteResultsRequest(currentPassword: "a secure password"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let deletion = try? response.content.decode(ResultDeletionResponse.self)
          XCTAssertTrue(deletion?.deleted ?? false)
          XCTAssertEqual(deletion?.removedCount, 1)
        })
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testDeveloperKeyRoutesAuthorizeOnlyOwnResults() async throws {
    let app = try await Application.make(.testing)
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "route-key@example.com", password: "a secure password", displayName: "Route Key"))
    let key = try await store.createDeveloperAccessKey(
      .init(name: "external-uploader"), accessToken: session.accessToken)
    let now = Date.now
    let resultID = UUID()

    do {
      try configure(app, authStore: store)
      try await app.test(.GET, "v1/developer-keys") { response async in
        XCTAssertEqual(response.status, .unauthorized)
      }
      try await app.test(
        .POST,
        "v1/developer-keys",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(CreateDeveloperAccessKeyRequest(name: "native-client"))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let created = try? response.content.decode(CreateDeveloperAccessKeyResponse.self)
          XCTAssertEqual(created?.key.name, "native-client")
          XCTAssertTrue(created?.accessKey.hasPrefix("tbak_") ?? false)
        })
      try await app.test(
        .GET,
        "v1/profiles/me",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        })
      try await app.test(
        .GET,
        "v1/leaderboards/rank",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        })
      try await app.test(
        .POST,
        "v1/results",
        beforeRequest: { request async throws in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
          try request.content.encode(result(id: resultID, wpm: 88, accuracy: 100, finishedAt: now))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
        })
      try await app.test(
        .GET,
        "v1/results?limit=1",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          let results = try? response.content.decode(ResultListResponse.self)
          XCTAssertEqual(results?.total, 1)
          XCTAssertEqual(results?.results.map(\.id), [resultID])
        })
      try await app.test(
        .GET,
        "v1/results/\(resultID.uuidString)",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertEqual((try? response.content.decode(AccountResultResponse.self))?.id, resultID)
        })
      try await app.test(
        .PATCH,
        "v1/results/\(resultID.uuidString)/tags",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        })
      try await app.test(
        .PATCH,
        "v1/developer-keys/\(key.key.id.uuidString)",
        beforeRequest: { request async throws in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
          try request.content.encode(UpdateDeveloperAccessKeyRequest(name: nil, enabled: false))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertFalse((try? response.content.decode(DeveloperAccessKey.self))?.enabled ?? true)
        })
      try await app.test(
        .POST,
        "v1/results",
        beforeRequest: { request async throws in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
          try request.content.encode(result(id: UUID(), wpm: 88, accuracy: 100, finishedAt: now))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .forbidden)
        })
      try await app.test(
        .GET,
        "v1/results",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .forbidden)
        })
      try await app.test(
        .DELETE,
        "v1/developer-keys/\(key.key.id.uuidString)",
        beforeRequest: { request async in
          request.headers.add(name: "Authorization", value: "Bearer \(session.accessToken)")
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .ok)
          XCTAssertTrue((try? response.content.decode(DeveloperAccessKeyDeletionResponse.self))?.deleted ?? false)
        })
      try await app.test(
        .POST,
        "v1/results",
        beforeRequest: { request async throws in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
          try request.content.encode(result(id: UUID(), wpm: 88, accuracy: 100, finishedAt: now))
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        })
      try await app.test(
        .GET,
        "v1/results",
        beforeRequest: { request async in
          request.headers.add(name: "X-Typebar-Access-Key", value: key.accessKey)
        },
        afterResponse: { response async in
          XCTAssertEqual(response.status, .unauthorized)
        })
      try await app.asyncShutdown()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
  }

  func testUkrainianResultCanBeSubmittedAndFilteredByLeaderboard() async throws {
    let store = try AuthStore(fileURL: nil, bcryptCost: 4)
    let session = try await store.register(
      .init(email: "ukrainian-result@example.com", password: "a secure password", displayName: "Ukrainian User"))
    let now = Date(timeIntervalSince1970: 1_735_689_600)
    let submission = try await store.submitResult(
      result(
        id: UUID(), wpm: 72, accuracy: 99, language: "ukrainian", finishedAt: now),
      accessToken: session.accessToken, now: now)
    XCTAssertTrue(submission.accepted)

    let leaderboard = try await store.leaderboard(
      .init(mode: "time", language: "ukrainian", period: "all", limit: 10), now: now)
    XCTAssertEqual(leaderboard.entries.map(\.wpm), [72])
  }

  func testLeaderboardPeriodsUseTodayYesterdayAndISOWeekBoundaries() async throws {
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
    let yesterday = try await store.leaderboard(
      .init(mode: "time", language: "english", period: "yesterday", limit: 10), now: now)
    let yesterdayRank = try await store.leaderboardRank(
      .init(mode: "time", language: "english", period: "yesterday", limit: 10),
      accessToken: session.accessToken, now: now)
    XCTAssertEqual(today.entries.map(\.wpm), [80])
    XCTAssertEqual(yesterday.entries.map(\.wpm), [90])
    XCTAssertEqual(week.entries.map(\.wpm), [90])
    XCTAssertEqual(yesterdayRank.entry?.wpm, 90)
  }

  private func result(
    id: UUID, wpm: Int, accuracy: Int, consistency: Double = 0, mode: String = "time",
    durationSeconds: Int? = 30, wordLimit: Int? = nil, restartCount: Int = 0,
    language: String = "english", finishedAt: Date
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
      id: id, mode: mode, language: language, durationSeconds: durationSeconds, wordLimit: wordLimit,
      wpm: wpm, rawWpm: rawWpm, accuracy: accuracy, consistency: consistency,
      errorCount: eventCount - correctCharacters, eventCount: eventCount,
      restartCount: restartCount,
      startedAt: finishedAt.addingTimeInterval(-elapsed),
      finishedAt: finishedAt)
  }

  private func configureTestApp(
    _ app: Application,
    moderationKey: String? = nil,
    oauthProviderClient: OAuthProviderClient? = nil,
    maintenanceMode: Bool = false
  ) throws {
    try configure(
      app,
      authStore: AuthStore(fileURL: nil, bcryptCost: 4),
      moderationKey: moderationKey,
      oauthProviderClient: oauthProviderClient,
      maintenanceMode: maintenanceMode)
  }
}
