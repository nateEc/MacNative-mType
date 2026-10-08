import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PublicProfilePersonalBestRenderingTests: XCTestCase {
  private var mountDefaults: UserDefaults?
  private func profile(empty: Bool = false, maximum: Bool = false, legacy: Bool = false) throws -> RemotePublicProfile {
    var rows: [[String: Any]] = empty ? [] : [("time", [15, 30, 60, 120]), ("words", [10, 25, 50, 100])].flatMap { mode, parameters in
      parameters.map { parameter in
        ["id": UUID().uuidString, "mode": mode, "mode2": String(parameter),
          mode == "time" ? "durationSeconds" : "wordLimit": parameter,
          "language": "english", "wpm": maximum ? 420 : 60,
          "preciseWpm": maximum ? 420.0 : 60.49, "rawWpm": maximum ? 420 : 120,
          "preciseRawWpm": maximum ? 420.0 : 120.0,
          "accuracy": 99, "preciseAccuracy": 98.75, "consistency": 80.25,
          "finishedAt": 100, "acceptedAtMilliseconds": 1_800_000_000_875,
          "personalBestOrigin": "accepted", "personalBestConfiguration": ["version": 1,
            "difficulty": "expert", "punctuation": true, "numbers": false, "lazyMode": true]]
      }
    }
    var root: [String: Any] = ["id": UUID().uuidString, "displayName": "Owned render profile",
      "joinedAt": 0, "completedResultCount": 0, "bestWPM": 0, "personalBests": [],
      "personalBestLedgerVersion": 1, "personalBestHistoryComplete": true, "personalBestSnapshots": rows]
    if legacy {
      for index in rows.indices {
        for key in ["mode2", "rawWpm", "preciseRawWpm", "personalBestConfiguration", "acceptedAtMilliseconds", "personalBestOrigin"] { rows[index].removeValue(forKey: key) }
      }
      rows[0].removeValue(forKey: "durationSeconds")
      rows[0]["language"] = "owned long language label for layout only"
      for key in ["personalBestLedgerVersion", "personalBestHistoryComplete", "personalBestSnapshots"] { root.removeValue(forKey: key) }
      root["personalBests"] = rows
    }
    return try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: root))
  }

  private func settle(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.layoutSubtreeIfNeeded()
  }

  private func withSettings(_ body: (AppSettings) throws -> Void) throws {
    let suite = "TypebarTests.profile-render.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}))
    try body(settings)
  }
  private func withMount(_ body: (NSWindow, NSHostingView<AnyView>) throws -> Void) throws {
    let suite = "TypebarTests.profile-render-mount.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    mountDefaults = defaults
    defer { mountDefaults = nil; defaults.removePersistentDomain(forName: suite) }
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 420, height: 900),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    try body(window, host)
  }
  private func root(_ content: some View, width: CGFloat = 420, padding: CGFloat = 32, dark: Bool = false) -> AnyView {
    AnyView(content.padding(padding).frame(width: width, alignment: .topLeading)
      .defaultAppStorage(mountDefaults!)
      .fixedSize(horizontal: false, vertical: true)
      .environment(\.colorScheme, dark ? .dark : .light)
      .background(Color(nsColor: .windowBackgroundColor)))
  }
  private func snapshot(_ host: NSHostingView<AnyView>, window: NSWindow, name: String, width: CGFloat = 420, dark: Bool = false) throws -> Data {
    settle(host)
    let fit = host.fittingSize
    XCTAssertEqual(fit.width, width, accuracy: 1)
    XCTAssertGreaterThan(fit.height, 20); XCTAssertLessThan(fit.height, 3000)
    window.setContentSize(.init(width: width, height: ceil(fit.height)))
    settle(host)
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    XCTAssertFalse(window.isVisible)
    XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(width))
    let background = try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
    XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), dark ? .darkAqua : .aqua,
      "AppKit appearance must match the SwiftUI color scheme")
    let backgroundBrightness = (background.redComponent + background.greenComponent + background.blueComponent) / 3
    if dark { XCTAssertLessThan(backgroundBrightness, 0.3) }
    else { XCTAssertGreaterThan(backgroundBrightness, 0.7) }
    var ink = 0, samples = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
        samples += 1
        if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          max(abs(pixel.redComponent - background.redComponent), abs(pixel.greenComponent - background.greenComponent),
            abs(pixel.blueComponent - background.blueComponent)) > 0.06 { ink += 1 }
      }
    }
    XCTAssertGreaterThan(Double(ink) / Double(max(1, samples)), 0.001, "Must draw actual content, not only a solid background")
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    print("PROFILE RENDER \(name) size=\(host.bounds.size) ink=\(ink)/\(samples)")
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
    return png
  }

  func testMountedProductionSummaryRendersInOneNeverVisibleWindow() throws {
    try withSettings { settings in try withMount { window, host in
      for (name, empty, maximum, dark) in [("normal-light", false, false, false),
        ("maximum-wph-dark", false, true, true), ("empty-light", true, false, false)] {
        settings.typingSpeedUnit = maximum ? .wph : .wpm
        settings.alwaysShowDecimalPlaces = maximum
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(PublicProfilePersonalBestsView(profile: try profile(empty: empty, maximum: maximum), settings: settings), dark: dark)
        _ = try snapshot(host, window: window, name: name, dark: dark)
        XCTAssertGreaterThan(host.bounds.height, 500)
      }
    } }
  }

  func testProductionLevelAndOwnerStreakStatesRenderSeriallyWithoutActivatingAWindow() throws {
    let today = 1_799_971_200_000.0, day = 86_400_000.0
    try withMount { window, host in
      for (name, xp, last, reference, offset, dark) in [
        ("progress-claimed-light", 249, Optional(today), Optional(today), Optional(0.0), false),
        ("progress-available-dark", 9_007_199_254_740_991, today - day, today - day, -0.5, true),
        ("progress-expired-narrow", 99, today - 3 * day, today - 3 * day, 12.0, false),
        ("progress-reset-dark", 100, today - 3 * day, today, 0.5, true),
        ("progress-empty-light", 0, nil, today, 0.0, false)
      ] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let claim = RemoteAccountStreakClaim(lastResultMilliseconds: last, streakReferenceMilliseconds: reference, dayBoundaryOffsetHours: offset)
        host.rootView = root(VStack(alignment: .leading, spacing: 16) {
          ProfileLevelProgressView(totalXP: xp)
          AccountStreakClaimContent(claim: claim, now: Date(timeIntervalSince1970: (today + 6 * 3_600_000) / 1000))
        }, width: 360, padding: 16, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 360, dark: dark)
      }
      window.appearance = NSAppearance(named: .aqua)
      host.rootView = root(VStack(alignment: .leading, spacing: 16) {
        ProfileLevelProgressView(totalXP: -1)
        AccountStreakClaimContent(claim: nil, now: .now)
        AccountStreakClaimContent(claim: .init(lastResultMilliseconds: today + day,
          streakReferenceMilliseconds: nil, dayBoundaryOffsetHours: nil), now: Date(timeIntervalSince1970: today / 1000))
      }, width: 360, padding: 16)
      _ = try snapshot(host, window: window, name: "progress-unavailable-and-clock-light", width: 360)
      XCTAssertFalse(window.isVisible)
    }
  }

  func testActualNativeProgressIndicatorTracksLevelResetsWithoutShowingAWindow() throws {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    try withMount { window, host in
      for xp in [0, 50, 99, 100, 174] {
        host.rootView = root(ProfileLevelProgressView(totalXP: xp), width: 360, padding: 16)
        settle(host)
        let indicators = descendants(host).compactMap { $0 as? NSProgressIndicator }
        print("LEVEL CONTROL xp=\(xp) nativeIndicators=\(indicators.count) views=\(descendants(host).map { String(describing: type(of: $0)) })")
        XCTAssertEqual(indicators.count, 1)
        let control = try XCTUnwrap(indicators.first), progress = try XCTUnwrap(ProfileLevelProgress(totalXP: xp))
        XCTAssertFalse(control.isIndeterminate); XCTAssertFalse(control.isHiddenOrHasHiddenAncestor)
        XCTAssertGreaterThan(control.maxValue, control.minValue)
        XCTAssertEqual((control.doubleValue - control.minValue) / (control.maxValue - control.minValue), progress.fraction, accuracy: 0.000_001)
        XCTAssertGreaterThan(control.bounds.width, 100)
        XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testProductionFriendsManagerRendersRelationsUnknownAndBusyWithoutRequestsOrWindowActivation() throws {
    func profile(_ name: String) throws -> RemotePublicProfile {
      try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: [
        "id": UUID().uuidString, "displayName": name, "joinedAt": 0, "completedResultCount": 12, "bestWPM": 80]))
    }
    let incoming = try profile("收到请求 · 自有测试"), outgoing = try profile("已发送 · 自有测试"),
      friend = try profile("已有好友 · 自有测试"), blocked = try profile("已屏蔽 · 自有测试"), new = try profile("新用户 · 自有测试")
    let full = ConnectionsSnapshot(connections: [(incoming, RemoteConnectionRelation.incomingRequest),
      (outgoing, .outgoingRequest), (friend, .friend)].map {
        .init(id: $0.0.id, profile: $0.0, relation: $0.1, updatedAt: .init(timeIntervalSince1970: 1))
      }, blockedProfiles: [blocked])
    let empty = ConnectionsSnapshot(connections: [], blockedProfiles: [])
    try withMount { window, host in
      for (name, value, searchResults, loading, sending, dark, height) in [
        ("manager-empty-light", Optional(empty), [RemotePublicProfile](), false, false, false, CGFloat(760)),
        ("manager-relations-light", full, [], false, false, false, 1050),
        ("manager-relations-dark", full, [], false, false, true, 1050),
        ("manager-loading-dark", nil, [], true, false, true, 420),
        ("manager-unknown-narrow", nil, [new], false, false, false, 620),
        ("manager-sending-dark", empty, [new], false, true, true, 900),
        ("manager-search-known-light", full, [incoming, outgoing, friend, blocked, new], false, false, false, 1600)
      ] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var calls = 0
        host.rootView = root(ConnectionsManagementContent(ownerID: UUID(), snapshot: value, searchResults: searchResults,
          isLoading: loading, isSearching: false, isMutating: sending,
          message: name == "manager-unknown-narrow" ? "操作未确认，服务端可能已收到；请刷新关系后再操作。" + String(repeating: "隔离测试中的长网络错误。", count: 8) : nil,
          searchMessage: searchResults.isEmpty ? "没有匹配的公开展示名。" : "找到 \(searchResults.count) 位用户。",
          query: .constant("自有测试"), search: { calls += 1 }, action: { _ in calls += 1 }, conversation: { _ in calls += 1 })
          .frame(height: height), width: 440, padding: 8, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 440, dark: dark)
        XCTAssertEqual(calls, 0); XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testProductionAddFriendFormRendersValidationFailureAndBusyWithoutRequestsOrWindowActivation() throws {
    let target = try profile()
    try withMount { window, host in
      for (name, status, sending, ready, dark, width) in [
        ("add-friend-empty-light", FriendNameStatus.idle, false, false, false, CGFloat(440)),
        ("add-friend-checking-dark", .checking, false, false, true, 440),
        ("add-friend-ready-light", .ready(target), false, true, false, 440),
        ("add-friend-existing-narrow", .existing(.incomingRequest), false, false, false, 360),
        ("add-friend-unavailable-dark", .failed(String(repeating: "隔离测试服务错误。", count: 12)), false, false, true, 360),
        ("add-friend-sending-dark", .ready(target), true, false, true, 440)
      ] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var calls = 0
        host.rootView = root(AddFriendForm(name: .constant("Owned target"), status: status, isSubmitting: sending,
          canSubmit: ready, message: "关系读取状态来自隔离 fixture。", retry: { calls += 1 },
          submit: { calls += 1 }, close: { calls += 1 }), width: width, padding: 0, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: width, dark: dark)
        XCTAssertEqual(calls, 0); XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testProductionLocalNoticesRenderHistoryAndFocusedStackWithoutClipboardOrWindowActivation() throws {
    try withMount { window, host in
      for (name, empty, dark, width) in [
        ("notice-history-empty-light", true, false, CGFloat(420)),
        ("notice-history-mixed-narrow-dark", false, true, 360),
        ("notice-history-mixed-light", false, false, 520)
      ] {
        let center = LocalNoticeCenter(); defer { center.clearAll() }
        if !empty {
          center.post("自有测试复制完成。", level: .success, options: .init(durationMilliseconds: 0))
          center.post(String(repeating: "自有长错误文字。", count: 10), level: .error,
            options: .init(durationMilliseconds: 0, title: "自有错误详情", details: .object(["owned": .bool(true)])))
          center.post("<b>自有网页格式</b>", options: .init(durationMilliseconds: 0, containsHTML: true))
        }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var calls = 0
        host.rootView = root(LocalNoticeHistoryContent(entries: Array(center.history.reversed()), copy: { _ in calls += 1 }),
          width: width, padding: 0, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: width, dark: dark)
        XCTAssertEqual(calls, 0)
      }
      let center = LocalNoticeCenter(); defer { center.clearAll() }
      center.post("自有普通错误，专注时隐藏。", level: .error)
      center.post("自有重要提示，专注时仍然可见。", level: .notice, options: .init(important: true, durationMilliseconds: 0))
      for (name, focused, dark) in [("notice-stack-all-dark", false, true), ("notice-stack-focused-light", true, false)] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(LocalNoticeStack(center: center, focused: focused), width: 360, padding: 10, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 360, dark: dark)
        XCTAssertEqual(center.history.count, 2); XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testProductionKnownHTMLAndConfigurationNoticesRenderWithoutOpeningLinksOrWindows() throws {
    try withMount { window, host in
      let center = LocalNoticeCenter(); defer { center.clearAll() }
      center.post("已应用自有配置：<br /><br />模式：words<br />标点：关闭<br />文字：&lt;br&gt; &amp; &#39; &#x2F; &#x60;",
        level: .success, options: .init(durationMilliseconds: 0, containsHTML: true))
      center.post("自有未支持格式：<b>保持原始文本</b>", options: .init(durationMilliseconds: 0, containsHTML: true))
      var calls = 0
      for (name, dark) in [("notice-format-history-light", false), ("notice-format-history-narrow-dark", true)] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(LocalNoticeHistoryContent(entries: Array(center.history.reversed()), copy: { _ in calls += 1 }),
          width: 360, padding: 0, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 360, dark: dark)
      }
      for (name, dark) in [("notice-format-stack-light", false), ("notice-format-stack-dark", true)] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(LocalNoticeStack(center: center, focused: false), width: 360, padding: 10, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 360, dark: dark)
      }
      XCTAssertEqual(calls, 0); XCTAssertFalse(window.isVisible)
    }
  }

  func testProductionFriendComparisonRendersWideNarrowAndLegacyWithoutRequestsOrWindowActivation() throws {
    func rich(_ name: String, legacy: Bool = false) throws -> RemotePublicProfile {
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any])
      json["id"] = UUID().uuidString; json["displayName"] = name
      json["startedTestCount"] = 300; json["completedResultCount"] = 123
      json["totalTypingSeconds"] = 123456.78; json["totalExperience"] = 123456
      json["streak"] = ["currentDays": 12, "longestDays": 42]
      if !legacy { json["practiceHistoryComplete"] = true }
      return try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: json))
    }
    let owner = try rich("本人对照 · 自有测试"), friend = try rich("好友统计与完整公开资料入口"), old = try rich("旧服务统计未知", legacy: true)
    let full = ConnectionsSnapshot(connections: [friend, old].map {
      .init(id: $0.id, profile: $0, relation: .friend, updatedAt: .init(timeIntervalSince1970: 1_800_000_000))
    }, blockedProfiles: [], ownerProfile: owner)
    let legacy = ConnectionsSnapshot(connections: [.init(id: old.id, profile: old, relation: .friend, updatedAt: .now)], blockedProfiles: [])
    try withMount { window, host in
      for (name, value, unit, width, dark) in [
        ("friends-comparison-wide-light", full, TypingSpeedUnit.wpm, CGFloat(1320), false),
        ("friends-comparison-wide-dark", full, .cpm, 1320, true),
        ("friends-comparison-narrow-light", full, .cps, 440, false),
        ("friends-comparison-legacy-dark", legacy, .wpm, 440, true)
      ] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var calls = 0
        host.rootView = root(FriendComparisonView(snapshot: value, unit: unit, openProfile: { _ in calls += 1 }, actions: { _ in
          AnyView(VStack { Button("解除好友") { calls += 1 }; Button("消息") { calls += 1 }; Button("屏蔽") { calls += 1 } })
        }), width: width, padding: 16, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: width, dark: dark)
        XCTAssertEqual(calls, 0); XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testProductionRelationshipStatesRenderWithoutRequestsOrWindowActivation() throws {
    try withMount { window, host in
      for (name, status, sending, dark) in [
        ("relationship-unavailable-light", ProfileRelationshipStatus.unavailable, false, false),
        ("relationship-ready-light", .notConnected, false, false),
        ("relationship-sending-dark", .notConnected, true, true),
        ("relationship-outgoing-light", .outgoingRequest, false, false),
        ("relationship-incoming-dark", .incomingRequest, false, true),
        ("relationship-friend-light", .friend, false, false),
        ("relationship-blocked-dark", .blocked, false, true),
        ("relationship-failed-narrow", .failed("发送未确认，服务端可能已收到；请刷新关系后再操作。" + String(repeating: "隔离测试中的网络失败详情。", count: 6)), false, false)
      ] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var calls = 0
        host.rootView = root(ProfileRelationshipContent(status: status, isSending: sending,
          refresh: { calls += 1 }, send: { calls += 1 }), width: 360, padding: 16, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 360, dark: dark)
        XCTAssertEqual(calls, 0); XCTAssertFalse(window.isVisible)
      }
    }
  }

  func testProductionAnnualActivityRendersLeapSparseEmptyAndIncompleteWithoutNetwork() throws {
    try withMount { window, host in
      var leap = Array<Int?>(repeating: nil, count: 366); leap[0] = 3; leap[59] = 7; leap[365] = 9
      for (name, years, year, complete, width, dark) in [
        ("annual-leap-light", ["2024": leap], 2024, true, 700.0, false),
        ("annual-sparse-dark", ["2025": [Int?(7)]], 2025, true, 360.0, true),
        ("annual-empty-light", [String: [Int?]](), 2023, true, 420.0, false),
        ("annual-incomplete-light", ["2024": leap], 2024, false, 700.0, false)
      ] {
        struct Fixture: Encodable { let id: UUID; let activityByYear: [String: [Int?]]; let practiceHistoryComplete: Bool }
        let value = try JSONDecoder().decode(RemoteAccountActivityYears.self, from: JSONEncoder().encode(
          Fixture(id: UUID(), activityByYear: years, practiceHistoryComplete: complete)))
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(AccountActivityYearContent(response: value, year: year), width: width, padding: 16, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: width, dark: dark)
      }
    }
  }

  func testProductionProfileEditorRendersAndPreservesActualTextEntryAcrossAccountRefresh() throws {
    try withMount { window, host in
      let suite = "TypebarTests.editor-render.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let account = AccountSession(defaults: defaults), id = UUID()
      let badge = RemotePublicProfileBadge(id: "owned", title: "原创练习徽章", systemImage: "keyboard")
      func user(bio: String, suspended: Bool = false, showAll: Bool = false) -> RemoteAccountUser {
        .init(id: id, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0,
          accountSuspended: suspended, profileDetails: .init(bio: bio, keyboard: "我的键盘",
            github: "owned", socialHandle: "owned_x", websiteURL: "https://owned.invalid", showActivity: false),
          authenticationMethods: [.password, .discord], availableBadges: [badge], selectedBadgeID: badge.id,
          showAllBadges: showAll)
      }
      func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
      account.currentUser = user(bio: "初始简介")
      let identity = AccountProfileEditIdentity(account: account)
      host.rootView = root(AccountProfileEditor(account: account, user: try XCTUnwrap(account.currentUser), identity: identity), width: 480, padding: 24)
      _ = try snapshot(host, window: window, name: "profile-editor-light", width: 480)
      let input = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
      XCTAssertEqual(input.string, "初始简介")
      input.string = "还没有保存的简介"; input.didChangeText()
      settle(host)
      account.currentUser = user(bio: "另一次刷新中的简介", showAll: true)
      _ = try snapshot(host, window: window, name: "profile-editor-unsaved-refresh-light", width: 480)
      XCTAssertEqual(try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first).string, "还没有保存的简介")
      XCTAssertEqual(account.currentUser?.profileDetails.bio, "另一次刷新中的简介")
      XCTAssertTrue(identity.isCurrent(account)); XCTAssertFalse(window.isVisible)
      window.appearance = NSAppearance(named: .darkAqua)
      host.rootView = root(AccountProfileEditor(account: account, user: try XCTUnwrap(account.currentUser), identity: identity), width: 480, padding: 24, dark: true)
      _ = try snapshot(host, window: window, name: "profile-editor-dark", width: 480, dark: true)
      account.currentUser = user(bio: "被封禁账户的已有简介", suspended: true)
      _ = try snapshot(host, window: window, name: "profile-editor-suspended-dark", width: 480, dark: true)
      account.currentUser = nil
      _ = try snapshot(host, window: window, name: "profile-editor-expired-dark", width: 480, dark: true)
      XCTAssertNil(account.currentUser); XCTAssertNil(account.statusMessage); XCTAssertFalse(account.isWorking)
    }
  }

  func testSameMountedSummaryObservesUnitChangesWhilePrimaryValuesStayInteger() throws {
    try withSettings { settings in try withMount { window, host in
      settings.typingSpeedUnit = .wpm; settings.alwaysShowDecimalPlaces = false
      let profile = try profile(), encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let before = try encoder.encode(profile)
      host.rootView = root(PublicProfilePersonalBestsView(profile: profile, settings: settings))
      let original = try snapshot(host, window: window, name: "live-wpm")
      settings.alwaysShowDecimalPlaces = true
      XCTAssertEqual(try snapshot(host, window: window, name: "live-wpm-decimals"), original)
      settings.typingSpeedUnit = .cpm
      XCTAssertNotEqual(try snapshot(host, window: window, name: "live-cpm"), original)
      settings.typingSpeedUnit = .wpm
      XCTAssertEqual(try snapshot(host, window: window, name: "live-restored"), original)
      XCTAssertEqual(try encoder.encode(profile), before)
    } }
  }

  func testSameMountedProductionDetailsObserveDecimalsAndUnitWithoutRebuildingTheView() throws {
    try withSettings { settings in try withMount { window, host in
      settings.typingSpeedUnit = .wpm; settings.alwaysShowDecimalPlaces = false
      let best = try XCTUnwrap(try profile().displayPersonalBests.first)
      host.rootView = root(PublicProfilePersonalBestDetails(best: best, settings: settings))
      let original = try snapshot(host, window: window, name: "detail-wpm")
      settings.alwaysShowDecimalPlaces = true
      XCTAssertNotEqual(try snapshot(host, window: window, name: "detail-decimals"), original)
      settings.typingSpeedUnit = .cps
      XCTAssertNotEqual(try snapshot(host, window: window, name: "detail-cps"), original)
      settings.typingSpeedUnit = .wpm; settings.alwaysShowDecimalPlaces = false
      XCTAssertEqual(try snapshot(host, window: window, name: "detail-restored"), original)
    } }
  }

  func testProductionDetailsRenderAtNarrowCardWidthWithMaximumAndUnknownLegacyFields() throws {
    try withSettings { settings in try withMount { window, host in
      settings.typingSpeedUnit = .wph; settings.alwaysShowDecimalPlaces = true
      for (name, legacy, dark) in [("narrow-maximum-dark", false, true), ("narrow-legacy-light", true, false)] {
        let best = try XCTUnwrap(try profile(maximum: !legacy, legacy: legacy).displayPersonalBests.first)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(VStack(alignment: .leading) {
          Text(best.configurationLabel).font(.subheadline.weight(.medium))
          PublicProfilePersonalBestDetails(best: best, settings: settings)
        }, width: 168, padding: 12, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 168, dark: dark)
        XCTAssertGreaterThan(host.bounds.height, 80)
      }
    } }
  }

  func testProductionLeaderboardCardsRenderWithoutShowingAWindow() throws {
    try withMount { window, host in
      for (name, dark, optedOut, position) in [
        ("rank-normal-light", false, false, ["rank": 2, "count": 3]),
        ("rank-large-dark", true, false, ["rank": 999_999_999, "count": 1_000_000_000]),
        ("rank-unknown-light", false, false, ["count": 0]),
        ("rank-optout-light", false, true, ["rank": 2, "count": 3])
      ] {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any])
        object["leaderboardOptedOut"] = optedOut
        object["allTimeLbs"] = ["time": ["15": ["english": position], "60": ["english": ["rank": 1, "count": 3]]]]
        let model = try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: object))
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(PublicProfileLeaderboardsView(profile: model), dark: dark)
        _ = try snapshot(host, window: window, name: name, dark: dark)
      }
    }
  }

  func testProductionProfileLoadStatesRenderInOneNeverVisibleWindowWithoutNetwork() throws {
    try withMount { window, host in
      for (name, dark, message) in [
        ("profile-loading-light", false, Optional<String>.none),
        ("profile-loading-dark", true, Optional<String>.none),
        ("profile-load-error-light", false, "资料读取失败，请重试：服务请求失败（HTTP 404）。"),
        ("profile-load-long-error-dark", true, String(repeating: "资料读取失败，请检查自建服务地址与网络连接。", count: 24))
      ] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(PublicProfileLoadPlaceholder(message: message, retry: {}, close: {}),
          padding: 0, dark: dark)
        _ = try snapshot(host, window: window, name: name, dark: dark)
        XCTAssertEqual(host.bounds.height, 620, accuracy: 1)
      }
    }
  }

  func testProductionSharedProfileConfirmationAndReadonlyPagesRenderWithoutNetworkOrActivation() throws {
    try withSettings { settings in try withMount { window, host in
      let suite = "TypebarTests.share-render.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let account = AccountSession(defaults: defaults), id = UUID()
      for (name, server, dark) in [("profile-share-confirm-light", "https://owned.invalid/base", false),
        ("profile-share-http-dark", "http://lan.invalid:9876/base", true),
        ("profile-share-http-long-dark", "http://lan.invalid:9876/" + String(repeating: "long-server-prefix/", count: 70), true)] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(SharedProfileConfirmation(target: try .init(server: server, profileID: id), confirm: {}, close: {}),
          width: 500, padding: 0, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 500, dark: dark)
        XCTAssertEqual(host.bounds.height, 420, accuracy: 1)
      }
      window.appearance = NSAppearance(named: .aqua)
      host.rootView = root(SharedProfileLinkView(route: .init(link: "typebar://profile?bad=1"), account: account, settings: settings), width: 500, padding: 0)
      _ = try snapshot(host, window: window, name: "profile-share-invalid-light", width: 500)
      host.rootView = root(PublicProfileView(profile: try profile(), account: account, settings: settings,
        allowsAccountActions: false, usesAnonymousMedia: true), padding: 0)
      _ = try snapshot(host, window: window, name: "profile-share-readonly-light")
      XCTAssertNil(account.currentUser); XCTAssertNil(account.statusMessage); XCTAssertFalse(account.isWorking)
    } }
  }

  func testProductionOwnerOverviewRendersWholeProfileWithoutPublicSheetFrameOrNetwork() throws {
    try withSettings { settings in try withMount { window, host in
      let suite = "TypebarTests.owner-render.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let account = AccountSession(defaults: defaults)
      for (name, dark, suspended, isOwner) in [("owner-overview-light", false, false, true),
        ("owner-overview-suspended-dark", true, true, true),
        ("public-profile-sheet-light", false, false, false), ("public-profile-suspended-dark", true, true, false)] {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any])
        object["completedResultCount"] = 20; object["startedTestCount"] = 25
        object["totalTypingSeconds"] = 3599.5; object["accountSuspended"] = suspended
        object["bestWPM"] = 60; object["highestConsistency"] = 80.25
        object["profileDetails"] = ["showActivity": false]
        object["activity"] = ["lastDay": 100, "testsByDays": [10, 10], "dayBoundaryOffsetHours": 0]
        object["allTimeLbs"] = ["time": ["15": ["english": ["rank": 2, "count": 3]]]]
        if !isOwner { object.removeValue(forKey: "activity") }
        if suspended { object.removeValue(forKey: "allTimeLbs") }
        let model = try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: object))
        account.currentUser = .init(id: model.id, email: "owned@example.invalid", displayName: model.displayName,
          totalExperience: 0, accountSuspended: suspended, availableBadges: [
            .init(id: "owned-1", title: "原创首个练习徽章", systemImage: "keyboard"),
            .init(id: "owned-2", title: "原创连续练习徽章", systemImage: "flame")], selectedBadgeID: "owned-1")
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(PublicProfileView(profile: model, account: account, settings: settings,
          isAccountOverview: isOwner, editProfile: isOwner ? {} : nil),
          width: isOwner ? 700 : 420, padding: isOwner ? 24 : 0, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: isOwner ? 700 : 420, dark: dark)
        if isOwner {
          XCTAssertGreaterThan(host.bounds.height, 620, "Owner content must scroll with the account page, not be trapped in the public sheet")
        } else {
          XCTAssertEqual(host.bounds.height, 620, accuracy: 1, "Public profile must retain its existing sheet frame")
        }
      }
    } }
  }
}
