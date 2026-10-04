import Foundation
import Vapor

public struct ResultExperienceEvidence: Content, Equatable, Sendable {
  public let version: Int
  public let characterCounts: [Int]
  public let scoringUnitBasis: ResultScoringUnitBasis
  public let durationSeconds: Double
  public let afkSeconds: Double
  public let punctuation: Bool
  public let numbers: Bool
  public let modifiers: [String]
  public init(version: Int = 1, characterCounts: [Int], scoringUnitBasis: ResultScoringUnitBasis,
    durationSeconds: Double, afkSeconds: Double, punctuation: Bool, numbers: Bool, modifiers: [String]) {
    self.version = version; self.characterCounts = characterCounts; self.scoringUnitBasis = scoringUnitBasis
    self.durationSeconds = durationSeconds; self.afkSeconds = afkSeconds
    self.punctuation = punctuation; self.numbers = numbers; self.modifiers = modifiers
  }
  var isValid: Bool {
    version == 1 && characterCounts.count == 4
      && characterCounts.allSatisfy { (0...9_000_000).contains($0) }
      && durationSeconds.isFinite && (0...3_600).contains(durationSeconds)
      && afkSeconds.isFinite && (0...durationSeconds).contains(afkSeconds)
      && modifiers.count <= ExperienceModifierCatalog.entries.count
      && Set(modifiers).count == modifiers.count
      && modifiers.allSatisfy { ExperienceModifierCatalog.entries[$0] != nil }
  }
  func matchesTiming(duration: Double, practiceTiming: ResultPracticeTiming?, restartCount: Int?) -> Bool {
    guard isValid, duration.isFinite, abs(durationSeconds - duration) <= 1e-9,
      let practiceTiming, practiceTiming.version == 1, let restartCount, (0...1_000).contains(restartCount),
      (0...(restartCount * 3_600_000)).contains(practiceTiming.priorAttemptEngagedMilliseconds),
      (0...3_600_000).contains(practiceTiming.terminalEngagedMilliseconds) else { return false }
    return abs((durationSeconds - afkSeconds) * 1_000
      - Double(practiceTiming.terminalEngagedMilliseconds)) <= 0.500001
  }
  func isBound(to metrics: ResultInputMetrics?, duration: Double, practiceTiming: ResultPracticeTiming?, language: String,
    restartCount: Int?) -> Bool {
    guard isValid, let metrics, metrics.isValid,
      characterCounts[0] == metrics.creditedUnits,
      // Prefix credit may include a space also diagnosed as extra. allCorrect
      // (not sent in this four-item tuple) is the conservation counter.
      characterCounts[0] + characterCounts[1] <= metrics.retainedUnits,
      characterCounts[1] + characterCounts[2] <= metrics.retainedUnits,
      (metrics.version == 1 ? .utf16 : metrics.scoringUnitBasis) == scoringUnitBasis,
      modifiers.contains("polyglot") == (language == "mixedLanguages"),
      matchesTiming(duration: duration, practiceTiming: practiceTiming, restartCount: restartCount) else { return false }
    return true
  }
  private enum CodingKeys: String, CodingKey {
    case version, characterCounts, scoringUnitBasis, durationSeconds, afkSeconds, punctuation, numbers, modifiers
  }
  public init(from decoder: Decoder) throws {
    let v = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try v.decode(Int.self, forKey: .version),
      characterCounts: try v.decode([Int].self, forKey: .characterCounts),
      scoringUnitBasis: try v.decode(ResultScoringUnitBasis.self, forKey: .scoringUnitBasis),
      durationSeconds: try v.decode(Double.self, forKey: .durationSeconds), afkSeconds: try v.decode(Double.self, forKey: .afkSeconds),
      punctuation: try v.decode(Bool.self, forKey: .punctuation), numbers: try v.decode(Bool.self, forKey: .numbers),
      modifiers: try v.decode([String].self, forKey: .modifiers))
    guard isValid else {
      throw DecodingError.dataCorruptedError(forKey: .version, in: v,
        debugDescription: "Experience evidence requires explicit bounded counts, timing and known modifier identities")
    }
  }
}

enum ExperienceEvidenceAdapter {
  static func input(for request: ResultSubmissionRequest) throws -> ExperienceCalculationInput {
    let duration = request.terminalTiming?.duration(mode: request.mode)
      ?? request.elapsedTime?.duration(mode: request.mode)
      ?? request.finishedAt.timeIntervalSince(request.startedAt)
    guard let evidence = request.experienceEvidence,
      evidence.isBound(to: request.inputMetrics, duration: duration,
        practiceTiming: request.practiceTiming, language: request.language, restartCount: request.restartCount),
      request.incompletePractice.map({ $0.isValid(restartCount: request.restartCount, practiceTiming: request.practiceTiming) }) ?? true,
      let metrics = request.inputMetrics else { throw ResultStoreError.invalidResult }
    return .init(mode: request.mode, accuracy: metrics.preciseAccuracy,
      durationSeconds: evidence.durationSeconds, afkSeconds: evidence.afkSeconds,
      characterCounts: evidence.characterCounts, punctuation: evidence.punctuation, numbers: evidence.numbers,
      funboxDifficultyLevels: evidence.modifiers.map { ExperienceModifierCatalog.entries[$0]!.difficulty },
      incompleteSeconds: request.practiceTiming.map { Double($0.priorAttemptEngagedMilliseconds) / 1_000 },
      incompleteAttempts: request.incompletePractice?.attempts.map { .init(accuracy: $0.accuracy, seconds: $0.seconds) })
  }
}
