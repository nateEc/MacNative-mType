import Foundation
import SwiftData

/// A completed run can remain useful for immediate review while being
/// ineligible for local history and remote publication. This mirrors the
/// reference result flow, which renders invalid results but deliberately
/// excludes them from saved result collections.
enum ResultEligibility: Equatable {
  case eligible
  case ineligible(ResultIneligibilityReason)

  var isEligible: Bool {
    if case .eligible = self { return true }
    return false
  }
}

enum ResultIneligibilityReason: Equatable {
  case tooShort
  case samePromptRepeat
  case typingSpeed
  case rawTypingSpeed
  case accuracy

  var resultSummary: String {
    switch self {
    case .tooShort: "测试时长或题量过短"
    case .samePromptRepeat: "使用同一提示词重测"
    case .typingSpeed: "速度超出可保存范围"
    case .rawTypingSpeed: "原始速度超出可保存范围"
    case .accuracy: "准确率未达到可保存范围"
    }
  }
}

/// Derives saving eligibility from the same observable result constraints as
/// Monkeytype's `TestLogic.finish()`. Typebar keeps the result sheet open in
/// every case; this policy controls only persistent local history, sync, and
/// publication side effects. The current-session practice total remains a
/// separate, non-persistent summary just as it does in the reference flow.
enum ResultEligibilityPolicy {
  private static let minimumTimedDuration: TimeInterval = 15
  private static let minimumWordLimit = 10
  private static let minimumMeasuredDuration: TimeInterval = 1
  private static let normalMinimumAccuracy = 75.0
  private static let reducedMinimumAccuracy = 50.0
  private static let standardMaximumWpm = 350.0
  private static let tenWordMaximumWpm = 420.0

  static func assessment(
    for result: CompletedTestResult, samePromptRepeat: Bool,
    allowsReducedAccuracyThreshold: Bool = false
  ) -> ResultEligibility {
    // Terminal failures have their own result presentation and saving rules.
    guard result.outcome == .completed else { return .eligible }
    guard !isTooShort(result) else { return .ineligible(.tooShort) }
    if samePromptRepeat, result.configuration.mode != .quote {
      return .ineligible(.samePromptRepeat)
    }

    let maximumWpm = maximumSavedWpm(for: result.configuration)
    if roundedToTwo(result.preciseWpm) < 0 || roundedToTwo(result.preciseWpm) > maximumWpm {
      return .ineligible(.typingSpeed)
    }
    if roundedToTwo(result.preciseRawWpm) < 0 || roundedToTwo(result.preciseRawWpm) > maximumWpm {
      return .ineligible(.rawTypingSpeed)
    }

    let minimumAccuracy = allowsReducedAccuracyThreshold
      ? reducedMinimumAccuracy : normalMinimumAccuracy
    let roundedAccuracy = roundedToTwo(result.preciseAccuracy)
    if roundedAccuracy < minimumAccuracy || roundedAccuracy > 100 {
      return .ineligible(.accuracy)
    }
    return .eligible
  }

  private static func isTooShort(_ result: CompletedTestResult) -> Bool {
    guard result.elapsedDuration.isFinite, result.elapsedDuration >= minimumMeasuredDuration else {
      return true
    }
    switch result.configuration.mode {
    case .time:
      guard let duration = result.configuration.duration else { return true }
      return duration == 0
        ? result.elapsedDuration < minimumTimedDuration
        : duration < minimumTimedDuration
    case .words:
      guard let wordLimit = result.configuration.wordLimit else { return true }
      return wordLimit == 0
        ? result.elapsedDuration < minimumTimedDuration
        : wordLimit < minimumWordLimit
    case .custom:
      switch result.configuration.customTextCompletion {
      case .finish:
        return false
      case .time:
        return (result.configuration.duration ?? 0) < minimumTimedDuration
      case .words:
        return (result.configuration.wordLimit ?? 0) < minimumWordLimit
      case .sections:
        return (result.configuration.customTextSectionLimit ?? 0) < minimumWordLimit
      }
    case .zen:
      return result.elapsedDuration < minimumTimedDuration
    case .quote:
      return false
    }
  }

  private static func maximumSavedWpm(for configuration: TestConfiguration) -> Double {
    configuration.mode == .words && configuration.wordLimit == 10
      ? tenWordMaximumWpm : standardMaximumWpm
  }

  private static func roundedToTwo(_ value: Double) -> Double {
    guard value.isFinite else { return .infinity }
    return (value * 100).rounded(.toNearestOrAwayFromZero) / 100
  }
}

enum ResultSavingPolicy {
  static func shouldPersist(outcome: TestOutcome, enabled: Bool) -> Bool {
    enabled && outcome == .completed
  }

  static func shouldPersist(
    outcome: TestOutcome, enabled: Bool, eligibility: ResultEligibility
  ) -> Bool {
    shouldPersist(outcome: outcome, enabled: enabled) && eligibility.isEligible
  }

  static func shouldPublish(localSaveState: LocalResultSaveState) -> Bool {
    localSaveState.isSaved
  }
}

/// Keeps the restart history that should become part of the next persisted
/// result. It is deliberately ephemeral: completed records retain the value,
/// while active practice can still be discarded without creating a database row.
struct PriorAttemptLedger: Equatable {
  private(set) var restartCount = 0
  private(set) var priorAttemptEngagedDuration: TimeInterval = 0

  mutating func recordRestart(engagedDuration: TimeInterval, savingEnabled: Bool) {
    guard savingEnabled else { return }
    append(engagedDuration: engagedDuration)
  }

  mutating func recordTerminalAttempt(
    engagedDuration: TimeInterval, outcome: TestOutcome, eligibility: ResultEligibility,
    savingEnabled: Bool
  ) {
    guard savingEnabled, shouldCarryTerminalAttempt(outcome: outcome, eligibility: eligibility) else {
      return
    }
    append(engagedDuration: engagedDuration)
  }

  mutating func clearAfterPersistingResult() {
    restartCount = 0
    priorAttemptEngagedDuration = 0
  }

  private mutating func append(engagedDuration: TimeInterval) {
    restartCount += 1
    guard engagedDuration.isFinite else { return }
    priorAttemptEngagedDuration += max(0, engagedDuration)
  }

  private func shouldCarryTerminalAttempt(
    outcome: TestOutcome, eligibility: ResultEligibility
  ) -> Bool {
    if outcome == .failed { return true }
    guard case .ineligible(.samePromptRepeat) = eligibility else { return false }
    return outcome == .completed
  }
}

enum LocalResultSaveState: Equatable {
  case notRequested
  case saved
  case failed(String)

  var isSaved: Bool {
    if case .saved = self { return true }
    return false
  }

  var canRetry: Bool {
    if case .failed = self { return true }
    return false
  }

  var failureMessage: String? {
    guard case .failed(let message) = self else { return nil }
    return message
  }
}

enum LocalResultSaveAttempt {
  static func perform(_ save: () throws -> Void) -> LocalResultSaveState {
    do {
      try save()
      return .saved
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}

enum ResultPublicationRetryPolicy {
  static func shouldQueue(_ error: Error) -> Bool {
    if error is URLError { return true }
    guard let accountError = error as? RemoteAccountError else { return false }
    if case .accountScopeChanged = accountError { return true }
    guard case .serverResponse(let statusCode, _) = accountError else { return false }
    return statusCode == 401 || statusCode == 408 || statusCode == 425 || statusCode == 429
      || (500...599).contains(statusCode)
  }
}

struct ResultPublicationScope: Codable, Equatable, Hashable, Sendable {
  let serverID: String
  let userID: UUID

  init(endpoint: String, userID: UUID) {
    serverID = RemoteServerScope(endpoint: endpoint).storageSuffix
    self.userID = userID
  }
}

/// A locally saved result that was completed before a user authenticated with
/// a result-publishing account. The value deliberately carries only the local
/// SwiftData record identifier: it never caches a result payload, endpoint,
/// account identity, or credential.
struct SignedOutResultClaim: Codable, Equatable, Identifiable {
  let resultID: UUID

  var id: UUID { resultID }
}

/// The complete local snapshot supplied to the explicit claim sheet. Keeping
/// the decoded result together with its candidate prevents the view from
/// depending on a second, asynchronously populated SwiftData query.
struct SignedOutResultClaimSheetState: Identifiable {
  let claim: SignedOutResultClaim
  let result: CompletedTestResult

  var id: UUID { claim.resultID }
}

/// Whether the single SwiftData record named by a signed-out claim can be
/// read at the moment a user signs in.
enum SignedOutResultClaimLocalRecordAvailability: Equatable {
  case present
  case absent
  case unavailable
}

/// The non-destructive decision the app makes before presenting an explicit
/// upload choice. A transient store failure must never be treated as proof
/// that the user's locally saved result was deleted.
enum SignedOutResultClaimDisposition: Equatable {
  case hidden
  case present(SignedOutResultClaim)
  case discard
}

/// Decides when an offline result can be offered for an explicit, one-time
/// upload after sign-in. This is intentionally separate from automatic result
/// publication: the user's global publication preference is never changed.
enum SignedOutResultClaimPolicy {
  static func shouldRecord(
    outcome: TestOutcome,
    localSaveState: LocalResultSaveState,
    isAuthenticatedForResultPublishing: Bool
  ) -> Bool {
    outcome == .completed && localSaveState.isSaved && !isAuthenticatedForResultPublishing
  }

  static func disposition(
    claim: SignedOutResultClaim?,
    isAuthenticatedForResultPublishing: Bool,
    localRecordAvailability: SignedOutResultClaimLocalRecordAvailability
  ) -> SignedOutResultClaimDisposition {
    guard let claim, isAuthenticatedForResultPublishing else { return .hidden }
    switch localRecordAvailability {
    case .present:
      return .present(claim)
    case .absent:
      return .discard
    case .unavailable:
      return .hidden
    }
  }
}

/// Persists only the most recent local result identifier awaiting an explicit
/// signed-in upload decision. Replacing the candidate preserves the reference
/// behavior's "last result" scope without duplicating sensitive result data.
final class SignedOutResultClaimStore {
  static let storageKey = "resultPublication.signedOutClaim.v1"

  private let defaults: UserDefaults
  private(set) var claim: SignedOutResultClaim?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    claim = defaults.data(forKey: Self.storageKey).flatMap {
      try? JSONDecoder().decode(SignedOutResultClaim.self, from: $0)
    }
  }

  func record(_ resultID: UUID) {
    claim = .init(resultID: resultID)
    guard let data = try? JSONEncoder().encode(claim) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }

  func clear() {
    claim = nil
    defaults.removeObject(forKey: Self.storageKey)
  }
}

private struct PendingResultPublication: Codable, Equatable, Hashable {
  let resultID: UUID
  let scope: ResultPublicationScope
}

/// Persists only result identifiers and their account/server ownership. The
/// result payload remains in SwiftData and credentials remain in Keychain.
final class PendingResultPublicationStore {
  static let storageKey = "resultPublication.pending.v1"

  private let defaults: UserDefaults
  private var entries: [PendingResultPublication]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    entries = []
    reload()
  }

  private func reload() {
    if let data = defaults.data(forKey: Self.storageKey),
      let decoded = try? JSONDecoder().decode([PendingResultPublication].self, from: data)
    {
      var seen = Set<PendingResultPublication>()
      entries = decoded.filter { seen.insert($0).inserted }
    } else {
      entries = []
    }
  }

  func resultIDs(for scope: ResultPublicationScope) -> [UUID] {
    reload()
    return entries.lazy.filter { $0.scope == scope }.map(\.resultID)
  }

  func enqueue(_ resultID: UUID, for scope: ResultPublicationScope) {
    reload()
    let entry = PendingResultPublication(resultID: resultID, scope: scope)
    guard !entries.contains(entry) else { return }
    entries.append(entry)
    persist()
  }

  func remove(_ resultID: UUID, for scope: ResultPublicationScope) {
    reload()
    let oldCount = entries.count
    entries.removeAll { $0.resultID == resultID && $0.scope == scope }
    if entries.count != oldCount { persist() }
  }

  func removeAll() {
    entries.removeAll()
    defaults.removeObject(forKey: Self.storageKey)
  }

  private func persist() {
    guard !entries.isEmpty else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    guard let data = try? JSONEncoder().encode(entries) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

struct ResultPublicationReceipt: Equatable {
  let message: String
  let dailyLeaderboardRank: Int?
}

enum ResultPublicationState: Equatable {
  case idle
  case sending
  case sent(ResultPublicationReceipt)
  case failed(String)
  case notice(String)

  var message: String? {
    switch self {
    case .idle: nil
    case .sending: "正在发送至自建服务…"
    case .sent(let receipt): receipt.message
    case .failed(let message), .notice(let message): message
    }
  }

  var canRetry: Bool {
    if case .failed = self { return true }
    return false
  }

  var isSending: Bool {
    if case .sending = self { return true }
    return false
  }

  var dailyLeaderboardRank: Int? {
    guard case .sent(let receipt) = self else { return nil }
    return receipt.dailyLeaderboardRank
  }
}

@Model
final class TestResultRecord {
  @Attribute(.unique) var id: UUID
  var configurationData: Data
  var outcome: String
  var startedAt: Date
  var finishedAt: Date
  var afkDuration: TimeInterval = 0
  var typedCharacterCount: Int
  var correctCharacterCount: Int
  var errorCount: Int
  var wpm: Int
  var rawWpm: Int
  var accuracy: Int
  var preciseWpm: Double?
  var preciseRawWpm: Double?
  var preciseAccuracy: Double?
  var storedRestartCount: Int?
  /// Optional so existing SwiftData stores expand without requiring a backfill.
  var storedPriorAttemptEngagedDuration: TimeInterval?
  var characterStatsData: Data?
  var keyDurationSamplesData: Data?
  var keySpacingSamplesData: Data?
  var keyOverlapDuration: TimeInterval?
  var tagsData: Data
  var quoteSourceData: Data?
  var prompt: String
  var replayEventsData: Data?
  var challengePresentationData: Data?

  init(result: CompletedTestResult) {
    id = result.id
    configurationData = (try? JSONEncoder().encode(result.configuration)) ?? Data()
    outcome = result.outcome.rawValue
    startedAt = result.startedAt
    finishedAt = result.finishedAt
    afkDuration = result.afkDuration
    typedCharacterCount = result.typedCharacterCount
    correctCharacterCount = result.correctCharacterCount
    errorCount = result.errorCount
    wpm = result.wpm
    rawWpm = result.rawWpm
    accuracy = result.accuracy
    preciseWpm = result.preciseWpm
    preciseRawWpm = result.preciseRawWpm
    preciseAccuracy = result.preciseAccuracy
    storedRestartCount = result.restartCount
    storedPriorAttemptEngagedDuration = result.priorAttemptEngagedDuration
    characterStatsData = try? JSONEncoder().encode(result.characterStats)
    keyDurationSamplesData = try? JSONEncoder().encode(result.keyDurationSamples)
    keySpacingSamplesData = try? JSONEncoder().encode(result.keySpacingSamples)
    keyOverlapDuration = result.keyOverlapDuration
    tagsData = (try? JSONEncoder().encode(ResultTagPolicy.normalized(result.tags))) ?? Data()
    quoteSourceData = result.quoteSource.flatMap { try? JSONEncoder().encode($0) }
    prompt = result.prompt
    replayEventsData = try? JSONEncoder().encode(result.replayEvents)
    challengePresentationData = result.challengePresentation.flatMap {
      try? JSONEncoder().encode($0)
    }
  }

  var configuration: TestConfiguration? {
    try? JSONDecoder().decode(TestConfiguration.self, from: configurationData)
  }

  var tags: [String] {
    get { (try? JSONDecoder().decode([String].self, from: tagsData)) ?? [] }
    set { tagsData = (try? JSONEncoder().encode(ResultTagPolicy.normalized(newValue))) ?? Data() }
  }

  var replayEvents: [TypingReplayEvent] {
    (replayEventsData.flatMap { try? JSONDecoder().decode([TypingReplayEvent].self, from: $0) })
      ?? []
  }

  var quoteSource: ResultQuoteSource? {
    quoteSourceData.flatMap { try? JSONDecoder().decode(ResultQuoteSource.self, from: $0) }
  }

  var challengePresentation: ChallengePresentationSnapshot? {
    challengePresentationData.flatMap {
      try? JSONDecoder().decode(ChallengePresentationSnapshot.self, from: $0)
    }
  }

  var restartCount: Int {
    max(0, storedRestartCount ?? 0)
  }

  var priorAttemptEngagedDuration: TimeInterval {
    guard let storedPriorAttemptEngagedDuration, storedPriorAttemptEngagedDuration.isFinite else {
      return 0
    }
    return max(0, storedPriorAttemptEngagedDuration)
  }

  var characterStats: ResultCharacterStats {
    characterStatsData.flatMap { try? JSONDecoder().decode(ResultCharacterStats.self, from: $0) }
      ?? .legacy(
        typedCharacterCount: typedCharacterCount,
        correctCharacterCount: correctCharacterCount)
  }

  var keyDurationSamples: [TimeInterval] {
    keyDurationSamplesData.flatMap { try? JSONDecoder().decode([TimeInterval].self, from: $0) }
      ?? []
  }

  var keySpacingSamples: [TimeInterval] {
    keySpacingSamplesData.flatMap { try? JSONDecoder().decode([TimeInterval].self, from: $0) }
      ?? []
  }

  var engagedDuration: TimeInterval {
    max(0, finishedAt.timeIntervalSince(startedAt) - afkDuration)
  }

  var totalEngagedDuration: TimeInterval {
    engagedDuration + priorAttemptEngagedDuration
  }

  var afkPercentage: Double {
    let elapsedDuration = max(0, finishedAt.timeIntervalSince(startedAt))
    guard elapsedDuration > 0 else { return 0 }
    return afkDuration / elapsedDuration * 100
  }

  func addTag(_ rawTag: String) {
    tags = ResultTagPolicy.appending(rawTag, to: tags)
  }

  func removeTag(_ tag: String) {
    tags = tags.filter { $0 != tag }
  }

  var portableResult: CompletedTestResult? {
    guard let configuration, let parsedOutcome = TestOutcome(rawValue: outcome) else { return nil }
    return CompletedTestResult(
      id: id,
      configuration: configuration,
      outcome: parsedOutcome,
      startedAt: startedAt,
      finishedAt: finishedAt,
      afkDuration: afkDuration,
      typedCharacterCount: typedCharacterCount,
      correctCharacterCount: correctCharacterCount,
      errorCount: errorCount,
      wpm: wpm,
      rawWpm: rawWpm,
      accuracy: accuracy,
      preciseWpm: preciseWpm,
      preciseRawWpm: preciseRawWpm,
      preciseAccuracy: preciseAccuracy,
      restartCount: restartCount,
      priorAttemptEngagedDuration: priorAttemptEngagedDuration,
      characterStats: characterStats,
      keyDurationSamples: keyDurationSamples,
      keySpacingSamples: keySpacingSamples,
      keyOverlapDuration: keyOverlapDuration ?? 0,
      tags: tags,
      quoteSource: quoteSource,
      prompt: prompt,
      replayEvents: replayEvents,
      challengePresentation: challengePresentation
    )
  }
}

enum ResultTagPolicy {
  static let maximumCount = 5
  static let maximumLength = 24

  static func normalized(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    return tags.compactMap(normalize).filter { tag in
      let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      return seen.insert(key).inserted
    }.prefix(maximumCount).map { $0 }
  }

  static func appending(_ rawTag: String, to tags: [String]) -> [String] {
    normalized(tags + [rawTag])
  }

  private static func normalize(_ rawTag: String) -> String? {
    let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !tag.isEmpty, tag.count <= maximumLength else { return nil }
    return tag
  }
}

enum ResultFilterPresetPolicy {
  static let maximumNameLength = 40

  static func normalizedName(_ rawName: String) -> String? {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= maximumNameLength else { return nil }
    return name
  }
}

/// Persists explicit filter-preset removals until every synced archive has
/// observed them. This prevents a stale device snapshot from resurrecting an
/// item the user intentionally deleted on another Mac.
struct ResultFilterPresetTombstoneStore {
  private static let storageKey = "resultFilterPreset.deletedIDs.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var deletedIDs: [UUID] {
    guard let data = defaults.data(forKey: Self.storageKey),
      let rawIDs = try? JSONDecoder().decode([UUID].self, from: data)
    else { return [] }
    return Array(Set(rawIDs)).sorted { $0.uuidString < $1.uuidString }
  }

  func contains(_ id: UUID) -> Bool {
    deletedIDs.contains(id)
  }

  func markDeleted(_ id: UUID) {
    recordDeletedIDs([id])
  }

  func recordDeletedIDs(_ ids: some Sequence<UUID>) {
    let combined = Set(deletedIDs).union(ids)
    save(combined)
  }

  func restore(_ ids: some Sequence<UUID>) {
    save(Set(deletedIDs).subtracting(ids))
  }

  func replaceDeletedIDs(_ ids: some Sequence<UUID>) {
    save(Set(ids))
  }

  func removeAll() {
    defaults.removeObject(forKey: Self.storageKey)
  }

  private func save(_ ids: Set<UUID>) {
    guard !ids.isEmpty else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    let sorted = ids.sorted { $0.uuidString < $1.uuidString }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

/// Persists explicit result removals until the synced archive has propagated
/// them. A stale device archive must not restore a result the user deleted.
struct ResultTombstoneStore {
  private static let storageKey = "result.deletedIDs.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var deletedIDs: [UUID] {
    guard let data = defaults.data(forKey: Self.storageKey),
      let rawIDs = try? JSONDecoder().decode([UUID].self, from: data)
    else { return [] }
    return Array(Set(rawIDs)).sorted { $0.uuidString < $1.uuidString }
  }

  func contains(_ id: UUID) -> Bool {
    deletedIDs.contains(id)
  }

  func markDeleted(_ id: UUID) {
    recordDeletedIDs([id])
  }

  func recordDeletedIDs(_ ids: some Sequence<UUID>) {
    save(Set(deletedIDs).union(ids))
  }

  func replaceDeletedIDs(_ ids: some Sequence<UUID>) {
    save(Set(ids))
  }

  func removeAll() {
    defaults.removeObject(forKey: Self.storageKey)
  }

  private func save(_ ids: Set<UUID>) {
    guard !ids.isEmpty else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    let sorted = ids.sorted { $0.uuidString < $1.uuidString }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

/// Persists explicit test-preset removals until the synced archive has
/// propagated them. Old device archives cannot silently restore a deletion.
struct PresetTombstoneStore {
  private static let storageKey = "preset.deletedIDs.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var deletedIDs: [UUID] {
    guard let data = defaults.data(forKey: Self.storageKey),
      let rawIDs = try? JSONDecoder().decode([UUID].self, from: data)
    else { return [] }
    return Array(Set(rawIDs)).sorted { $0.uuidString < $1.uuidString }
  }

  func contains(_ id: UUID) -> Bool {
    deletedIDs.contains(id)
  }

  func markDeleted(_ id: UUID) {
    recordDeletedIDs([id])
  }

  func recordDeletedIDs(_ ids: some Sequence<UUID>) {
    save(Set(deletedIDs).union(ids))
  }

  func replaceDeletedIDs(_ ids: some Sequence<UUID>) {
    save(Set(ids))
  }

  func removeAll() {
    defaults.removeObject(forKey: Self.storageKey)
  }

  private func save(_ ids: Set<UUID>) {
    guard !ids.isEmpty else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    let sorted = ids.sorted { $0.uuidString < $1.uuidString }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

/// Persists explicit saved-text removals until the synced archive has
/// propagated them. A stale archive cannot silently restore deleted text.
struct SavedTextTombstoneStore {
  private static let storageKey = "savedText.deletedIDs.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var deletedIDs: [UUID] {
    guard let data = defaults.data(forKey: Self.storageKey),
      let rawIDs = try? JSONDecoder().decode([UUID].self, from: data)
    else { return [] }
    return Array(Set(rawIDs)).sorted { $0.uuidString < $1.uuidString }
  }

  func contains(_ id: UUID) -> Bool { deletedIDs.contains(id) }
  func markDeleted(_ id: UUID) { recordDeletedIDs([id]) }
  func recordDeletedIDs(_ ids: some Sequence<UUID>) { save(Set(deletedIDs).union(ids)) }
  func replaceDeletedIDs(_ ids: some Sequence<UUID>) { save(Set(ids)) }
  func removeAll() { defaults.removeObject(forKey: Self.storageKey) }

  private func save(_ ids: Set<UUID>) {
    guard !ids.isEmpty else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    let sorted = ids.sorted { $0.uuidString < $1.uuidString }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

/// Persists deletions for user-authored settings collections that live inside
/// an AppSettings snapshot. Both collections use stable UUIDs in v9 archives.
struct CustomizationTombstoneStore {
  private enum Kind: String {
    case theme = "customTheme"
    case keyboardLayout = "customKeyboardLayout"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var deletedThemeIDs: [UUID] { deletedIDs(for: .theme) }
  var deletedKeyboardLayoutIDs: [UUID] { deletedIDs(for: .keyboardLayout) }

  func containsDeletedTheme(_ id: UUID) -> Bool { deletedThemeIDs.contains(id) }
  func containsDeletedKeyboardLayout(_ id: UUID) -> Bool {
    deletedKeyboardLayoutIDs.contains(id)
  }

  func markDeletedTheme(_ id: UUID) { record([id], for: .theme) }
  func markDeletedKeyboardLayout(_ id: UUID) { record([id], for: .keyboardLayout) }
  func replaceDeletedThemeIDs(_ ids: some Sequence<UUID>) { replace(ids, for: .theme) }
  func replaceDeletedKeyboardLayoutIDs(_ ids: some Sequence<UUID>) {
    replace(ids, for: .keyboardLayout)
  }

  func removeAll() {
    for kind in [Kind.theme, .keyboardLayout] { defaults.removeObject(forKey: storageKey(for: kind)) }
  }

  private func deletedIDs(for kind: Kind) -> [UUID] {
    guard let data = defaults.data(forKey: storageKey(for: kind)),
      let rawIDs = try? JSONDecoder().decode([UUID].self, from: data)
    else { return [] }
    return Array(Set(rawIDs)).sorted { $0.uuidString < $1.uuidString }
  }

  private func record(_ ids: some Sequence<UUID>, for kind: Kind) {
    replace(Set(deletedIDs(for: kind)).union(ids), for: kind)
  }

  private func replace(_ ids: some Sequence<UUID>, for kind: Kind) {
    let uniqueIDs = Set(ids)
    guard !uniqueIDs.isEmpty else {
      defaults.removeObject(forKey: storageKey(for: kind))
      return
    }
    let sorted = uniqueIDs.sorted { $0.uuidString < $1.uuidString }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    defaults.set(data, forKey: storageKey(for: kind))
  }

  private func storageKey(for kind: Kind) -> String { "customization.\(kind.rawValue).deletedIDs.v1" }
}

@Model
final class ResultFilterPresetRecord {
  @Attribute(.unique) var id: UUID
  var name: String
  var filterData: Data
  var createdAt: Date

  init?(name: String, filter: ResultHistoryFilter) {
    guard let name = ResultFilterPresetPolicy.normalizedName(name),
      let filterData = try? JSONEncoder().encode(filter)
    else { return nil }
    id = UUID()
    self.name = name
    self.filterData = filterData
    createdAt = .now
  }

  init?(portablePreset: NamedResultFilterPreset) {
    guard portablePreset.isValid,
      let filterData = try? JSONEncoder().encode(portablePreset.filter)
    else { return nil }
    id = portablePreset.id
    name = portablePreset.name
    self.filterData = filterData
    createdAt = portablePreset.createdAt
  }

  var filter: ResultHistoryFilter? {
    try? JSONDecoder().decode(ResultHistoryFilter.self, from: filterData)
  }

  var portablePreset: NamedResultFilterPreset? {
    guard let filter else { return nil }
    return .init(id: id, name: name, filter: filter, createdAt: createdAt)
  }
}
