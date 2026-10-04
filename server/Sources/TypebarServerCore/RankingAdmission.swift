import Foundation
import Vapor

public enum RankingEnvironment: String, Codable, Sendable {
  case production, development
  public static func fromEnvironment(_ value: String?) throws -> Self {
    guard let value else { return .production }
    guard let environment = Self(rawValue: value) else { throw ResultStoreError.invalidResult }
    return environment
  }
}

/// Anonymous controls needed to evaluate ranking eligibility, not a claim of
/// anti-cheat proof. No prompt, replay, key identity or account data.
public struct ResultRankingEvidence: Content, Equatable, Sendable {
  public let version: Int
  public let stopOnLetter: Bool
  public let modifiers: [String]
  public init(version: Int = 1, stopOnLetter: Bool, modifiers: [String]) {
    self.version = version; self.stopOnLetter = stopOnLetter; self.modifiers = modifiers
  }
  var isValid: Bool {
    version == 1 && modifiers.count <= ExperienceModifierCatalog.entries.count
      && Set(modifiers).count == modifiers.count
      && modifiers.allSatisfy { ExperienceModifierCatalog.entries[$0] != nil }
  }
  private enum CodingKeys: String, CodingKey { case version, stopOnLetter, modifiers }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version),
      stopOnLetter: try values.decode(Bool.self, forKey: .stopOnLetter),
      modifiers: try values.decode([String].self, forKey: .modifiers))
    guard isValid else { throw DecodingError.dataCorruptedError(forKey: .modifiers, in: values,
      debugDescription: "Invalid ranking control evidence") }
  }
}

struct RankingAdmissionInput: Codable, Equatable, Sendable {
  let mode: String
  let accuracy: Double
  let bailedOut: Bool
  let modifiers: [String]
  let stopOnLetter: Bool
  let evidence: ResultRankingEvidence?

  static func make(_ request: ResultSubmissionRequest, evidence override: ResultRankingEvidence? = nil) throws -> Self {
    let evidence = override ?? request.rankingEvidence
    guard evidence?.isValid != false else {
      throw ResultStoreError.invalidResult
    }
    if let evidence {
      guard evidence.modifiers.contains("polyglot") == (request.language == "mixedLanguages") else {
        throw ResultStoreError.invalidResult
      }
      if let experience = request.experienceEvidence,
        Set(evidence.modifiers) != Set(experience.modifiers) { throw ResultStoreError.invalidResult }
    }
    return .init(mode: request.mode, accuracy: request.inputMetrics?.preciseAccuracy ?? Double(request.accuracy),
      bailedOut: request.bailedOut == true,
      modifiers: evidence?.modifiers ?? request.experienceEvidence?.modifiers ?? [],
      stopOnLetter: evidence?.stopOnLetter ?? false, evidence: evidence)
  }
}

struct RankingAdmissionContext: Codable, Equatable, Sendable {
  let previousTypingSeconds: Double
  let minimumTypingSeconds: Int
  let environment: RankingEnvironment
  let accountExcluded: Bool
  var userEligible: Bool {
    !accountExcluded && (environment == .development || previousTypingSeconds > Double(minimumTypingSeconds))
  }
}

struct RankingAdmissionDecision: Codable, Equatable, Sendable {
  let personalBestEligible: Bool
  let speedEligible: Bool
  let weeklyExperienceEligible: Bool
}

/// Immutable acceptance-time snapshot. Missing on historical awards means
/// unknown, not an inferred production admission or a retroactive repricing.
struct RankingAdmission: Codable, Equatable, Sendable {
  let version: Int
  let input: RankingAdmissionInput
  let context: RankingAdmissionContext
  let decision: RankingAdmissionDecision

  static func evaluate(_ input: RankingAdmissionInput, context: RankingAdmissionContext) -> RankingAdmissionDecision {
    let allowedModifiers = input.modifiers.allSatisfy {
      ExperienceModifierCatalog.entries[$0]?.allowsPersonalBest == true
    }
    let allowedResult = allowedModifiers && !input.bailedOut && !(input.stopOnLetter && input.accuracy < 100)
    return .init(personalBestEligible: allowedResult && input.mode != "quote",
      speedEligible: allowedResult && context.userEligible,
      weeklyExperienceEligible: context.userEligible)
  }
  func validate() throws {
    guard version == 1, ["time", "words", "quote", "custom", "zen"].contains(input.mode),
      input.accuracy.isFinite, (0...100).contains(input.accuracy),
      input.modifiers.count <= ExperienceModifierCatalog.entries.count,
      Set(input.modifiers).count == input.modifiers.count,
      input.modifiers.allSatisfy({ ExperienceModifierCatalog.entries[$0] != nil }),
      input.evidence.map({ $0.isValid && $0.stopOnLetter == input.stopOnLetter
        && $0.modifiers == input.modifiers }) ?? !input.stopOnLetter,
      context.previousTypingSeconds.isFinite, (0...9_007_199_254_740_991).contains(context.previousTypingSeconds),
      (0...TypebarLeaderboardEligibilityPolicy.maximumMinimumPracticeSeconds).contains(context.minimumTypingSeconds),
      decision == Self.evaluate(input, context: context) else { throw ResultStoreError.invalidResult }
  }
}
