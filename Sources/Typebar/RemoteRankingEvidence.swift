import Foundation

extension InputRules {
  /// Match existing rule normalization for legacy Boolean-only in-memory
  /// snapshots without misclassifying an explicitly selected word stop.
  var stopsOnLetterForRanking: Bool {
    stopOnErrorMode == .letter || (stopOnError && stopOnErrorMode == .off)
  }
}

/// Saved controls only; no prompt, replay, account eligibility or award claim.
struct RemoteRankingEvidence: Codable, Equatable, Sendable {
  let version: Int
  let stopOnLetter: Bool
  let modifiers: [String]
  var isValid: Bool {
    version == 1 && modifiers.count <= RemoteExperienceEvidence.knownModifiers.count
      && Set(modifiers).count == modifiers.count
      && modifiers.allSatisfy { RemoteExperienceEvidence.knownModifiers.contains($0) }
  }
  init(version: Int = 1, stopOnLetter: Bool, modifiers: [String]) {
    self.version = version; self.stopOnLetter = stopOnLetter; self.modifiers = modifiers
  }
  private enum CodingKeys: String, CodingKey { case version, stopOnLetter, modifiers }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version),
      stopOnLetter: try values.decode(Bool.self, forKey: .stopOnLetter),
      modifiers: try values.decode([String].self, forKey: .modifiers))
    guard isValid else { throw DecodingError.dataCorruptedError(forKey: .modifiers, in: values,
      debugDescription: "Unsupported ranking controls") }
  }
}

enum RemoteRankingEvidencePolicy {
  static func prepare(_ result: CompletedTestResult, capabilities: RemoteServiceCapabilities?) throws -> RemoteRankingEvidence? {
    let configuration = result.configuration
    guard capabilities?.supportsResultRankingEvidence == true else {
      // Older result wires cannot represent these controls. Preserve the local
      // result and pending submission rather than silently change semantics.
      guard !configuration.rules.stopsOnLetterForRanking,
        configuration.language != .mixedLanguages,
        configuration.modifiers.allSatisfy(CurrentPersonalBestPolicy.modifierAllowsPersonalBest)
      else { throw RemoteAccountError.serverMessage("当前服务不支持完整榜单控制信息，请先升级自建服务；本机成绩保留。") }
      return nil
    }
    let evidence = RemoteRankingEvidence(stopOnLetter: configuration.rules.stopsOnLetterForRanking,
      modifiers: configuration.modifiers.filter { $0 != .lazyLatin }.map(\.rawValue)
        + (configuration.language == .mixedLanguages ? ["polyglot"] : []))
    guard evidence.isValid else { throw RemoteAccountError.serverMessage("榜单控制信息无效；本机成绩保留。") }
    return evidence
  }
}
