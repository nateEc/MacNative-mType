import Foundation

/// Projection of saved terminal evidence, not an award or authority to alter XP.
struct RemoteExperienceEvidence: Codable, Equatable, Sendable {
  let version: Int
  let characterCounts: [Int]
  let scoringUnitBasis: ResultScoringUnitBasis
  let durationSeconds: Double
  let afkSeconds: Double
  let punctuation: Bool
  let numbers: Bool
  let modifiers: [String]

  static var knownModifiers: Set<String> {
    Set(TestModifier.funboxPreferenceCases.map(\.rawValue) + ["polyglot"])
  }
  var isValid: Bool {
    version == 1 && characterCounts.count == 4
      && characterCounts.allSatisfy { (0...9_000_000).contains($0) }
      && durationSeconds.isFinite && (0...3_600).contains(durationSeconds)
      && afkSeconds.isFinite && (0...durationSeconds).contains(afkSeconds)
      && modifiers.count <= Self.knownModifiers.count && Set(modifiers).count == modifiers.count
      && modifiers.allSatisfy { Self.knownModifiers.contains($0) }
  }
  func matchesTiming(duration: Double, practiceTiming: RemoteResultPracticeTiming?, restartCount: Int?) -> Bool {
    guard isValid, duration.isFinite, abs(durationSeconds - duration) <= 1e-9,
      let practiceTiming, practiceTiming.version == 1, let restartCount, (0...1_000).contains(restartCount),
      (0...(restartCount * 3_600_000)).contains(practiceTiming.priorAttemptEngagedMilliseconds),
      (0...3_600_000).contains(practiceTiming.terminalEngagedMilliseconds) else { return false }
    return abs((durationSeconds - afkSeconds) * 1_000 - Double(practiceTiming.terminalEngagedMilliseconds)) <= 0.500001
  }
  private enum CodingKeys: String, CodingKey {
    case version, characterCounts, scoringUnitBasis, durationSeconds, afkSeconds, punctuation, numbers, modifiers
  }
  init(version: Int = 1, characterCounts: [Int], scoringUnitBasis: ResultScoringUnitBasis,
    durationSeconds: Double, afkSeconds: Double, punctuation: Bool, numbers: Bool, modifiers: [String]) {
    self.version = version; self.characterCounts = characterCounts; self.scoringUnitBasis = scoringUnitBasis
    self.durationSeconds = durationSeconds; self.afkSeconds = afkSeconds
    self.punctuation = punctuation; self.numbers = numbers; self.modifiers = modifiers
  }
  init(from decoder: Decoder) throws {
    let v = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try v.decode(Int.self, forKey: .version),
      characterCounts: try v.decode([Int].self, forKey: .characterCounts),
      scoringUnitBasis: try v.decode(ResultScoringUnitBasis.self, forKey: .scoringUnitBasis),
      durationSeconds: try v.decode(Double.self, forKey: .durationSeconds),
      afkSeconds: try v.decode(Double.self, forKey: .afkSeconds),
      punctuation: try v.decode(Bool.self, forKey: .punctuation), numbers: try v.decode(Bool.self, forKey: .numbers),
      modifiers: try v.decode([String].self, forKey: .modifiers))
    guard isValid else {
      throw DecodingError.dataCorruptedError(forKey: .version, in: v,
        debugDescription: "Experience evidence needs supported, finite terminal counts, timing and modifier identities")
    }
  }
}

enum RemoteExperienceEvidencePolicy {
  static func prepare(_ result: CompletedTestResult, capabilities: RemoteServiceCapabilities?) throws -> RemoteExperienceEvidence? {
    // Additive pre-reward capability: older services keep the existing XP path.
    guard capabilities?.supportsResultExperienceEvidence == true else { return nil }
    // Explicit unit classification and attempts must already have been saved.
    // Never reconstruct legacy history from replay, visible errors or a prompt.
    guard let units = result.characterStats.sourceUnits, let metrics = result.inputMetrics else { return nil }
    let basis = result.characterStats.sourceUnitBasis ?? .utf16
    let required = metrics.publicationVersion(nativeCharacterCount: result.typedCharacterCount)
    guard (required == 1 && (capabilities?.supportsResultInputMetrics == true
      || capabilities?.supportsResultInputMetricsV2 == true))
      || (required == 2 && capabilities?.supportsResultInputMetricsV2 == true),
      capabilities?.supportsResultPracticeTiming == true else { throw invalid() }
    let counts = [units.correctWord, units.incorrect, units.extra, units.missed]
    let modifiers = result.configuration.modifiers.filter { $0 != .lazyLatin }.map(\.rawValue)
      + (result.configuration.language == .mixedLanguages ? ["polyglot"] : [])
    let evidence = RemoteExperienceEvidence(characterCounts: counts, scoringUnitBasis: basis,
      durationSeconds: result.elapsedDuration, afkSeconds: result.afkDuration,
      punctuation: result.configuration.contentOptions.includePunctuation,
      numbers: result.configuration.contentOptions.includeNumbers, modifiers: modifiers)
    guard evidence.isValid, (0...9_000_000).contains(units.allCorrect),
      units.allCorrect + units.incorrect + units.extra == metrics.retainedUnits,
      units.correctWord == metrics.creditedUnits,
      (metrics.version == 1 ? .utf16 : metrics.scoringUnitBasis) == basis,
      metrics.version == 1 || metrics.version == 2,
      (0...1_800_000).contains(metrics.totalAttempts), (0...metrics.totalAttempts).contains(metrics.correctAttempts),
      valid(metrics),
      evidence.matchesTiming(duration: result.elapsedDuration,
        practiceTiming: RemoteResultPracticeTiming(result: result), restartCount: result.restartCount)
    else { throw invalid() }
    return evidence
  }
  private static func valid(_ metrics: ResultInputMetrics) -> Bool {
    guard metrics.retainedUnits >= 0, (0...metrics.retainedUnits).contains(metrics.creditedUnits) else { return false }
    if metrics.version == 1 {
      return metrics.retainedInputUnits == nil && metrics.scoringUnitBasis == nil
        && metrics.retainedUnits <= metrics.totalAttempts
    }
    guard metrics.version == 2, let input = metrics.retainedInputUnits,
      (0...metrics.totalAttempts).contains(input), metrics.retainedUnits >= input else { return false }
    return metrics.scoringUnitBasis == .utf16 ? metrics.retainedUnits == input
      : metrics.scoringUnitBasis == .koreanJamo && metrics.retainedUnits <= input * 5
  }
  private static func invalid() -> RemoteAccountError {
    .serverMessage("完整 XP 计量需要匹配的计分单位、输入计数和活动时长能力；证据不符时保留本机成绩。")
  }
}
