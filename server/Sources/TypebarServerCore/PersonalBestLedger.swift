import Foundation

enum PersonalBestLedgerError: Error { case invalidState }

/// Numeric clock fields survive the store's whole-second ISO date encoding.
/// No text, tags, replay, or identity secrets belong in a public PB snapshot.
struct PersonalBestSnapshot: Codable, Equatable {
  enum Origin: String, Codable { case accepted, legacyHistory }
  let userID: UUID
  let resultID: UUID
  let mode: String
  let mode2: String
  let language: String
  let wpm: Int
  let rawWpm: Int
  let speedPrecision: ResultSpeedPrecision?
  let accuracy: Int
  let preciseAccuracy: Double?
  let consistency: Double
  let personalBestConfiguration: ResultPersonalBestConfiguration?
  let completedAtReferenceTime: Double
  let acceptedAtMilliseconds: Int?
  let origin: Origin

  var effectiveWpm: Double { speedPrecision?.wpm ?? Double(wpm) }
  var effectiveAccuracy: Double { preciseAccuracy ?? Double(accuracy) }
  var finishedAt: Date { Date(timeIntervalSinceReferenceDate: completedAtReferenceTime) }
  var groupKey: String {
    // Structured encoding is unnecessary here: mode/language are validated
    // identifiers, controls have finite domains, UUID never contains '/'.
    let config = personalBestConfiguration.map {
      "\($0.difficulty)/\($0.punctuation)/\($0.numbers)/\($0.lazyMode)"
    } ?? "unknown"
    return "\(userID)/\(mode)/\(mode2)/\(language)/\(config)"
  }
  var leaderboardKey: String { "\(userID)/\(mode2)/\(language)" }
  var isOfficialLeaderboardMode: Bool { mode == "time" && ["15", "60"].contains(mode2) }

  static func make(_ request: ResultSubmissionRequest, userID: UUID,
    acceptedAt: Date?, origin: Origin) throws -> Self {
    let mode2 = ResultMode2Policy.resolved(mode: request.mode, explicit: request.mode2,
      duration: request.durationSeconds, words: request.wordLimit) ?? "unknown"
    let clock = acceptedAt.map { ($0.timeIntervalSince1970 * 1_000).rounded(.down) }
    guard clock.map({ $0.isFinite && (0...8_640_000_000_000_000).contains($0) }) ?? true else {
      throw PersonalBestLedgerError.invalidState
    }
    let value = Self(userID:userID,resultID:request.id,mode:request.mode,mode2:mode2,
      language:request.language,wpm:request.wpm,rawWpm:request.rawWpm,speedPrecision:request.speedPrecision,
      accuracy:request.accuracy,preciseAccuracy:request.inputMetrics?.preciseAccuracy,consistency:request.consistency,
      personalBestConfiguration:request.personalBestConfiguration,
      completedAtReferenceTime:request.finishedAt.timeIntervalSinceReferenceDate,
      acceptedAtMilliseconds:clock.map(Int.init),origin:origin)
    try value.validate(); return value
  }
  func validate() throws {
    guard ["time","words","custom","zen"].contains(mode),
      ResultMode2Policy.isValid(mode2,mode:mode)
        || (mode2 == "unknown" && ["time","words"].contains(mode) && personalBestConfiguration == nil),
      !language.isEmpty, language.count <= 100, !language.contains("/"),
      (0...420).contains(wpm), (0...500).contains(rawWpm), rawWpm >= wpm,
      speedPrecision.map({ $0.matches(wpm:wpm,rawWpm:rawWpm) }) ?? true,
      (0...100).contains(accuracy), preciseAccuracy.map({ $0.isFinite && (0...100).contains($0)
        && Int($0.rounded()) == accuracy }) ?? true,
      consistency.isFinite, (0...100).contains(consistency), completedAtReferenceTime.isFinite,
      personalBestConfiguration?.isValid != false,
      acceptedAtMilliseconds.map({ (0...8_640_000_000_000_000).contains($0) }) ?? (origin == .legacyHistory),
      origin != .legacyHistory || acceptedAtMilliseconds == nil else { throw PersonalBestLedgerError.invalidState }
  }
  func matches(_ request: ResultSubmissionRequest) -> Bool {
    resultID == request.id && mode == request.mode && mode2 == (ResultMode2Policy.resolved(mode:request.mode,
      explicit:request.mode2,duration:request.durationSeconds,words:request.wordLimit) ?? "unknown")
      && language == request.language && wpm == request.wpm && rawWpm == request.rawWpm
      && speedPrecision == request.speedPrecision && accuracy == request.accuracy
      && preciseAccuracy == request.inputMetrics?.preciseAccuracy && consistency == request.consistency
      && personalBestConfiguration == request.personalBestConfiguration
      // Only old whole-second ISO records need a compatibility tolerance.
      // Reported speed/elapsed records retain a separate exact numeric date.
      && abs(finishedAt.timeIntervalSince(request.finishedAt))
        < (request.speedPrecision != nil || request.elapsedTime != nil ? 0.000001 : 1)
  }
  var response: PublicProfileBestResponse {
    .init(id:resultID,mode:mode,durationSeconds:mode == "time" ? Int(mode2) : nil,
      wordLimit:mode == "words" ? Int(mode2) : nil,language:language,wpm:wpm,accuracy:accuracy,
      preciseAccuracy:preciseAccuracy,consistency:consistency,finishedAt:finishedAt,preciseWpm:speedPrecision?.wpm,
      mode2:mode2,rawWpm:rawWpm,preciseRawWpm:speedPrecision?.rawWpm,
      personalBestConfiguration:personalBestConfiguration,acceptedAtMilliseconds:acceptedAtMilliseconds,
      personalBestOrigin:origin.rawValue)
  }
}

struct PersonalBestReceipt: Codable {
  let version: Int
  let candidate: PersonalBestSnapshot?
  let isPersonalBest: Bool
  func validate(reward: ExperienceAwardRecord) throws {
    guard version == 1, !isPersonalBest || candidate != nil,
      (candidate != nil) == (reward.rankingAdmission?.decision.personalBestEligible == true) else {
      throw PersonalBestLedgerError.invalidState
    }
    if let candidate {
      try candidate.validate()
      guard candidate.origin == .accepted, candidate.userID == reward.userID, candidate.resultID == reward.resultID,
        candidate.personalBestConfiguration == reward.personalBestConfiguration,
        candidate.speedPrecision == reward.speedPrecision,
        candidate.mode == reward.rankingAdmission?.input.mode,
        candidate.effectiveAccuracy == reward.rankingAdmission?.input.accuracy,
        // Complete XP records store the admission second, not client finish.
        reward.context != nil || abs(candidate.finishedAt.timeIntervalSince(reward.finishedAt)) < 1,
        reward.acceptedAt.map({ abs(Double(candidate.acceptedAtMilliseconds!) / 1_000 - $0.timeIntervalSince1970) < 1 }) == true
      else { throw PersonalBestLedgerError.invalidState }
    }
  }
}

extension PersonalBestSnapshot {
  private enum CodingKeys: String, CodingKey {
    case userID,resultID,mode,mode2,language,wpm,rawWpm,speedPrecision,accuracy,preciseAccuracy,
      consistency,personalBestConfiguration,completedAtReferenceTime,acceptedAtMilliseconds,origin
  }
  init(from decoder: Decoder) throws {
    let v = try decoder.container(keyedBy:CodingKeys.self)
    self.init(userID:try v.decode(UUID.self,forKey:.userID),resultID:try v.decode(UUID.self,forKey:.resultID),
      mode:try v.decode(String.self,forKey:.mode),mode2:try v.decode(String.self,forKey:.mode2),
      language:try v.decode(String.self,forKey:.language),wpm:try v.decode(Int.self,forKey:.wpm),
      rawWpm:try v.decode(Int.self,forKey:.rawWpm),
      speedPrecision:v.contains(.speedPrecision) ? try v.decode(ResultSpeedPrecision.self,forKey:.speedPrecision) : nil,
      accuracy:try v.decode(Int.self,forKey:.accuracy),
      preciseAccuracy:v.contains(.preciseAccuracy) ? try v.decode(Double.self,forKey:.preciseAccuracy) : nil,
      consistency:try v.decode(Double.self,forKey:.consistency),
      personalBestConfiguration:v.contains(.personalBestConfiguration) ? try v.decode(ResultPersonalBestConfiguration.self,forKey:.personalBestConfiguration) : nil,
      completedAtReferenceTime:try v.decode(Double.self,forKey:.completedAtReferenceTime),
      acceptedAtMilliseconds:v.contains(.acceptedAtMilliseconds) ? try v.decode(Int.self,forKey:.acceptedAtMilliseconds) : nil,
      origin:try v.decode(Origin.self,forKey:.origin))
    try validate()
  }
}

extension PersonalBestReceipt {
  private enum CodingKeys: String, CodingKey { case version,candidate,isPersonalBest }
  init(from decoder: Decoder) throws {
    let v = try decoder.container(keyedBy:CodingKeys.self)
    self.init(version:try v.decode(Int.self,forKey:.version),
      candidate:v.contains(.candidate) ? try v.decode(PersonalBestSnapshot.self,forKey:.candidate) : nil,
      isPersonalBest:try v.decode(Bool.self,forKey:.isPersonalBest))
  }
}

/// Separate personal and leaderboard books. Deleting result history cannot
/// mutate either. Public clear erases both; internal personal-only clear does not.
struct PersonalBestLedger: Codable {
  var version = 1
  var entries: [PersonalBestSnapshot] = []
  var leaderboardEntries: [PersonalBestSnapshot] = []
  var legacyUsers: Set<UUID> = []
  // Compatibility-only derived day boards have no Redis row to purge. Keep
  // precise result identities so a clear and new acceptance in the same
  // millisecond cannot either resurrect old rows or hide the new one.
  var dailyClearResultKeys: Set<String> = []

  @discardableResult mutating func accept(_ candidate: PersonalBestSnapshot) -> Bool {
    if let index = entries.firstIndex(where: { $0.groupKey == candidate.groupKey }) {
      guard candidate.effectiveWpm > entries[index].effectiveWpm else { return false }
      entries[index] = candidate
    } else { entries.append(candidate) }
    // Source DAL only writes LB PB when this result created a personal PB and
    // is non-lazy time15/60. Its selection then includes every existing variant.
    if candidate.isOfficialLeaderboardMode, candidate.personalBestConfiguration?.lazyMode == false {
      for value in entries.filter({ $0.userID == candidate.userID && $0.mode == "time" && $0.mode2 == candidate.mode2 }) {
        retainLeaderboard(value)
      }
    } else if candidate.isOfficialLeaderboardMode, candidate.personalBestConfiguration == nil {
      // Older Typebar clients never sent grouping controls. Preserve their
      // own unknown-config board view without pretending lazy=false or using
      // this submission to promote a known lazy group.
      retainLeaderboard(candidate)
    }
    return true
  }
  mutating func retainLeaderboard(_ candidate: PersonalBestSnapshot) {
    if let index = leaderboardEntries.firstIndex(where: { $0.leaderboardKey == candidate.leaderboardKey }) {
      if candidate.effectiveWpm > leaderboardEntries[index].effectiveWpm { leaderboardEntries[index] = candidate }
    } else { leaderboardEntries.append(candidate) }
  }
  mutating func clear(userID: UUID, personalOnly: Bool = false) {
    entries.removeAll { $0.userID == userID }
    if !personalOnly {
      leaderboardEntries.removeAll { $0.userID == userID }; legacyUsers.remove(userID)
      dailyClearResultKeys = dailyClearResultKeys.filter { !$0.hasPrefix("\(userID)/") }
    }
  }
  mutating func clearLeaderboard(userID: UUID) { leaderboardEntries.removeAll { $0.userID == userID } }
  func validate(users: Set<UUID>, awards: [ExperienceAwardRecord]) throws {
    guard version == 1, legacyUsers.isSubset(of:users) else { throw PersonalBestLedgerError.invalidState }
    let rewards = Dictionary(uniqueKeysWithValues: awards.map { ("\($0.userID)/\($0.resultID)", $0) })
    guard dailyClearResultKeys.allSatisfy({ rewards[$0] != nil }) else { throw PersonalBestLedgerError.invalidState }
    for (values, personal) in [(entries,true),(leaderboardEntries,false)] {
      var keys = Set<String>()
      for value in values {
        try value.validate()
        guard users.contains(value.userID), keys.insert(personal ? value.groupKey : value.leaderboardKey).inserted,
          personal || value.isOfficialLeaderboardMode,
          let reward = rewards["\(value.userID)/\(value.resultID)"] else { throw PersonalBestLedgerError.invalidState }
        if value.origin == .accepted {
          guard reward.personalBestReceipt?.isPersonalBest == true,
            reward.personalBestReceipt?.candidate == value else { throw PersonalBestLedgerError.invalidState }
        } else {
          guard reward.personalBestReceipt == nil, legacyUsers.contains(value.userID),
            reward.personalBestConfiguration == value.personalBestConfiguration, reward.speedPrecision == value.speedPrecision,
            reward.context != nil || abs(reward.finishedAt.timeIntervalSince(value.finishedAt)) < 1 else { throw PersonalBestLedgerError.invalidState }
        }
      }
    }
  }
}
