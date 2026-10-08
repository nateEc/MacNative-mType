import Foundation
import XCTest
@testable import Typebar

final class AccountProfileEditorTests: XCTestCase {
  func testAccountAndSettingsUseTheSameEditorAndOwnerBadgeBoundary() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let profile = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/CloudSyncView.swift"), encoding: .utf8)
    let preferences = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PreferencesView.swift"), encoding: .utf8)
    let overview = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/AccountProfileOverview.swift"), encoding: .utf8)
    XCTAssertTrue(overview.contains("AccountProfileEditorSheet("), "The account page needs a real editor, not a generic settings shortcut")
    XCTAssertTrue(profile.contains("editProfile?()"))
    XCTAssertTrue(profile.contains("AccountProfileBadgePresentation("), "Only an authenticated owner projection may reveal private badges")
    XCTAssertTrue(preferences.contains("AccountProfileEditor("), "Settings and account must share field/save behavior")
    XCTAssertFalse(preferences.contains("@State private var profileBio"), "Two divergent editing drafts must not survive extraction")
  }

  private let badges: [RemotePublicProfileBadge] = [
    .init(id: "owned-1", title: "Owned first", systemImage: "star"),
    .init(id: "owned-2", title: "Owned second", systemImage: "keyboard"),
    .init(id: "owned-3", title: "Owned third", systemImage: "flame")]

  private func user(id: UUID = UUID(), bio: String = "Original", suspended: Bool = false,
    showAll: Bool = false, selected: String? = "owned-1") -> RemoteAccountUser {
    .init(id: id, email: "owned@example.invalid", displayName: "Owned", totalExperience: 500,
      accountSuspended: suspended, profileDetails: .init(bio: bio, keyboard: "Owned keys",
        github: "owned", socialHandle: "owned_x", websiteURL: "https://owned.invalid",
        showActivity: false, showDiscordAvatar: true), authenticationMethods: [.password, .discord],
      availableBadges: badges, selectedBadgeID: selected, showAllBadges: showAll)
  }

  @MainActor private func session(_ body: (AccountSession) async throws -> Void) async throws {
    let suite = "TypebarTests.profile-editor.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = user()
    try await body(account)
  }

  func testDraftRoundTripsEveryFieldAndSelectedNoneWithoutMutatingSourceUser() {
    let original = user(), draft = AccountProfileDraft(user: original)
    XCTAssertEqual(draft.details, original.profileDetails); XCTAssertEqual(draft.selectedBadgeID, "owned-1")
    var changed = draft
    changed.bio = "Unsaved"; changed.keyboard = "New keys"; changed.github = "new"
    changed.socialHandle = "new_x"; changed.websiteURL = "https://new.invalid"
    changed.showActivity.toggle(); changed.showDiscordAvatar.toggle(); changed.selectedBadgeID = ""
    XCTAssertEqual(changed.details, .init(bio: "Unsaved", keyboard: "New keys", github: "new",
      socialHandle: "new_x", websiteURL: "https://new.invalid", showActivity: true, showDiscordAvatar: false))
    XCTAssertTrue(changed.canSave(for: original)); XCTAssertEqual(original.profileDetails.bio, "Original")
    XCTAssertEqual(AccountProfileDraft(user: original), draft)
  }

  func testDraftChecksExistingLengthContractOwnershipAndSuspension() {
    let original = user()
    let limits: [(WritableKeyPath<AccountProfileDraft, String>, Int)] = [
      (\.bio, 250), (\.keyboard, 75), (\.github, 39), (\.socialHandle, 15), (\.websiteURL, 200)]
    for (field, maximum) in limits {
      var draft = AccountProfileDraft(user: original)
      draft[keyPath: field] = String(repeating: "a", count: maximum)
      XCTAssertTrue(draft.canSave(for: original))
      draft[keyPath: field].append("a"); XCTAssertFalse(draft.canSave(for: original))
    }
    var draft = AccountProfileDraft(user: original)
    draft.selectedBadgeID = "foreign"; XCTAssertFalse(draft.canSave(for: original))
    draft.selectedBadgeID = "owned-3"; XCTAssertTrue(draft.canSave(for: original))
    XCTAssertFalse(draft.canSave(for: user(suspended: true)))
  }

  @MainActor func testSuccessfulSaveAppliesCanonicalResponseAndInvalidatesActualOverviewIdentity() async throws {
    try await session { account in
      let identity = AccountProfileEditIdentity(account: account), revision = UUID()
      let before = AccountProfileOverviewLoadID(account: account, revision: revision)
      let saved = self.user(id: try XCTUnwrap(account.currentUser?.id), bio: "Canonical trimmed")
      let applied = await account.performAccountProfileEdit(identity: identity, successMessage: "Saved") {
        XCTAssertTrue(account.isWorking); return saved
      }
      XCTAssertTrue(applied); XCTAssertEqual(account.currentUser, saved); XCTAssertEqual(account.statusMessage, "Saved")
      XCTAssertFalse(account.isWorking); XCTAssertTrue(identity.isCurrent(account))
      XCTAssertNotEqual(before, AccountProfileOverviewLoadID(account: account, revision: revision))
      XCTAssertTrue(account.remoteResults.isEmpty); XCTAssertNil(account.accountTagHistoryCache)
    }
  }

  @MainActor func testFailedSaveLeavesUserAndDraftIntactAndRetryCanSucceed() async throws {
    try await session { account in
      let original = try XCTUnwrap(account.currentUser), identity = AccountProfileEditIdentity(account: account)
      var draft = AccountProfileDraft(user: original); draft.bio = "Unsaved draft"
      let failed = await account.performAccountProfileEdit(identity: identity, successMessage: "Saved") {
        throw URLError(.notConnectedToInternet)
      }
      XCTAssertFalse(failed); XCTAssertEqual(account.currentUser, original)
      XCTAssertEqual(draft.bio, "Unsaved draft"); XCTAssertNotNil(account.statusMessage); XCTAssertFalse(account.isWorking)
      let saved = self.user(id: original.id, bio: draft.bio)
      let retried = await account.performAccountProfileEdit(identity: identity, successMessage: "Saved") { saved }
      XCTAssertTrue(retried); XCTAssertEqual(account.currentUser?.profileDetails.bio, draft.bio)
    }
  }

  @MainActor func testExpiredDraftNeverStartsTransportAcrossLogoutServerAndABA() async throws {
    try await session { account in
      let original = try XCTUnwrap(account.currentUser), endpoint = account.endpoint
      for mode in 0...2 {
        let identity = AccountProfileEditIdentity(account: account)
        if mode == 0 { account.currentUser = nil }
        else if mode == 1 { account.currentUser = nil; account.currentUser = original }
        else {
          XCTAssertTrue(account.updateEndpoint("https://other-owned.invalid"))
          XCTAssertTrue(account.updateEndpoint(endpoint)); account.currentUser = original
        }
        account.statusMessage = "New session"
        var calls = 0
        let applied = await account.performAccountProfileEdit(identity: identity, successMessage: "Saved") { calls += 1; return original }
        XCTAssertFalse(applied); XCTAssertEqual(calls, 0); XCTAssertEqual(account.statusMessage, "New session")
        account.currentUser = original
      }
    }
  }

  @MainActor func testLateSuccessAndFailureCannotReplaceReauthenticatedUserOrStatus() async throws {
    try await session { account in
      for fails in [false, true] {
        let original = try XCTUnwrap(account.currentUser), identity = AccountProfileEditIdentity(account: account)
        let fresh = self.user(id: original.id, bio: "New session")
        let applied = await account.performAccountProfileEdit(identity: identity, successMessage: "Stale") {
          account.currentUser = nil; account.currentUser = fresh; account.statusMessage = "New session"
          if fails { throw URLError(.timedOut) }
          return original
        }
        XCTAssertFalse(applied); XCTAssertEqual(account.currentUser, fresh)
        XCTAssertEqual(account.statusMessage, "New session"); XCTAssertFalse(account.isWorking)
      }
    }
  }

  @MainActor func testWrongOwnerBusySuspendedCancelledAndConcurrentRefreshDoNotApply() async throws {
    try await session { account in
      let original = try XCTUnwrap(account.currentUser), identity = AccountProfileEditIdentity(account: account)
      let wrong = await account.performAccountProfileEdit(identity: identity, successMessage: "Wrong") { self.user() }
      XCTAssertFalse(wrong); XCTAssertEqual(account.currentUser, original)
      var calls = 0
      account.isWorking = true
      let busy = await account.performAccountProfileEdit(identity: identity, successMessage: "Wrong") { calls += 1; return original }
      XCTAssertFalse(busy); XCTAssertTrue(account.isWorking); account.isWorking = false
      account.currentUser = self.user(id: original.id, suspended: true)
      let banned = await account.performAccountProfileEdit(identity: identity, successMessage: "Wrong") { calls += 1; return original }
      XCTAssertFalse(banned); XCTAssertEqual(calls, 0)
      account.currentUser = original
      let task = Task { @MainActor in
        await account.performAccountProfileEdit(identity: identity, successMessage: "Wrong") {
          withUnsafeCurrentTask { $0?.cancel() }; return original
        }
      }
      let cancelled = await task.value; XCTAssertFalse(cancelled); XCTAssertEqual(account.currentUser, original)
      let fresh = self.user(id: original.id, bio: "Unrelated fresh data")
      let raced = await account.performAccountProfileEdit(identity: identity, successMessage: "Wrong") {
        account.currentUser = fresh; return original
      }
      XCTAssertFalse(raced); XCTAssertEqual(account.currentUser, fresh)
      XCTAssertTrue(account.statusMessage?.contains("可能已保存") == true); XCTAssertFalse(account.isWorking)
    }
  }

  @MainActor func testProfileEditDoesNotReleaseBusyFlagClaimedByAnotherOperation() async throws {
    try await session { account in
      let original = try XCTUnwrap(account.currentUser), identity = AccountProfileEditIdentity(account: account)
      let applied = await account.performAccountProfileEdit(identity: identity, successMessage: "Stale") {
        account.currentUser = nil
        account.isWorking = true // Another account operation claims the shared busy state.
        return original
      }
      XCTAssertFalse(applied); XCTAssertNil(account.currentUser)
      XCTAssertTrue(account.isWorking, "The retired profile operation must not unlock someone else's work")
      account.isWorking = false
    }
  }

  func testPrivateInventoryIsIndependentOfDisclosureButNeverUsedByVisitorsOrWrongOwner() throws {
    let original = user()
    let profile = try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: [
      "id": original.id.uuidString, "displayName": "Owned", "joinedAt": 0,
      "completedResultCount": 0, "bestWPM": 0, "accountSuspended": true,
      "earnedBadges": [], "personalBests": []]))
    let owner = AccountProfileBadgePresentation(profile: profile, isAccountOverview: true, user: original)
    XCTAssertTrue(owner.isPrivateInventory); XCTAssertEqual(owner.selected?.id, "owned-1")
    XCTAssertEqual(owner.additional.map(\.id), ["owned-2", "owned-3"])
    for (isOwner, user) in [(false, Optional(original)), (true, nil), (true, Optional(self.user()))] {
      let visitor = AccountProfileBadgePresentation(profile: profile, isAccountOverview: isOwner, user: user)
      XCTAssertFalse(visitor.isPrivateInventory); XCTAssertNil(visitor.selected); XCTAssertTrue(visitor.additional.isEmpty)
    }
    let noSelection = AccountProfileBadgePresentation(profile: profile, isAccountOverview: true,
      user: user(id: original.id, selected: nil))
    XCTAssertNil(noSelection.selected); XCTAssertEqual(noSelection.additional.map(\.id), badges.map(\.id))
    var publicObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    publicObject["selectedBadge"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(badges[0]))
    publicObject["earnedBadges"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([badges[0], badges[1]]))
    let disclosed = try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: publicObject))
    let visitor = AccountProfileBadgePresentation(profile: disclosed, isAccountOverview: false, user: original)
    XCTAssertEqual(visitor.selected?.id, "owned-1"); XCTAssertEqual(visitor.additional.map(\.id), ["owned-2"])
    XCTAssertFalse(visitor.isPrivateInventory)
  }

  func testDraftDefaultsAndSaveMappingMatchPinnedEditorSubmitFixtures() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-profile-editor.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable {
      struct Draft: Decodable {
        let bio: String; let keyboard: String; let github: String; let twitter: String; let website: String
        let showActivityOnPublicProfile: Bool; let badgeId: Int
        var details: RemoteProfileDetails { .init(bio: bio, keyboard: keyboard, github: github,
          socialHandle: twitter, websiteURL: website, showActivity: showActivityOnPublicProfile) }
        var nativeBadgeID: String { badgeId < 0 ? "" : "owned-\(badgeId)" }
      }
      let defaults: Draft; let value: Draft; let selectedBadgeId: Int
    }
    struct Root: Decodable { let fixtures: [Fixture] }
    let fixtures = try JSONDecoder().decode(Root.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 32)
    for fixture in fixtures {
      let sourceUser = RemoteAccountUser(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0,
        profileDetails: fixture.defaults.details, availableBadges: badges,
        selectedBadgeID: fixture.defaults.nativeBadgeID.isEmpty ? nil : fixture.defaults.nativeBadgeID)
      var draft = AccountProfileDraft(user: sourceUser)
      XCTAssertEqual(draft.details, fixture.defaults.details); XCTAssertEqual(draft.selectedBadgeID, fixture.defaults.nativeBadgeID)
      draft.bio = fixture.value.bio; draft.showActivity = fixture.value.showActivityOnPublicProfile
      draft.selectedBadgeID = fixture.value.nativeBadgeID
      XCTAssertEqual(draft.details, fixture.value.details); XCTAssertEqual(draft.selectedBadgeID, fixture.value.nativeBadgeID)
      XCTAssertTrue(draft.canSave(for: sourceUser))
    }
  }
}
