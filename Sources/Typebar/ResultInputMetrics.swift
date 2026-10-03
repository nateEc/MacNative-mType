import Foundation

enum ResultScoringUnitBasis: String, Codable, Sendable {
  case utf16, koreanJamo
}

/// Anonymous terminal counters for a version-negotiated submission. Accuracy
/// attempts survive deletion; speed credit concerns only the retained words.
/// Neither can be reconstructed from a legacy result's visible error count.
struct ResultInputMetrics: Codable, Equatable, Sendable {
  let version: Int
  let correctAttempts: Int
  let totalAttempts: Int
  let creditedUnits: Int
  let retainedUnits: Int
  let retainedInputUnits: Int?
  let scoringUnitBasis: ResultScoringUnitBasis?

  init(version: Int, correctAttempts: Int, totalAttempts: Int, creditedUnits: Int,
    retainedUnits: Int, retainedInputUnits: Int? = nil, scoringUnitBasis: ResultScoringUnitBasis? = nil) {
    self.version = version; self.correctAttempts = correctAttempts; self.totalAttempts = totalAttempts
    self.creditedUnits = creditedUnits; self.retainedUnits = retainedUnits
    self.retainedInputUnits = retainedInputUnits; self.scoringUnitBasis = scoringUnitBasis
  }

  private enum CodingKeys: String, CodingKey {
    case version, correctAttempts, totalAttempts, creditedUnits, retainedUnits,
      retainedInputUnits, scoringUnitBasis
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version),
      correctAttempts: try values.decode(Int.self, forKey: .correctAttempts),
      totalAttempts: try values.decode(Int.self, forKey: .totalAttempts),
      creditedUnits: try values.decode(Int.self, forKey: .creditedUnits),
      retainedUnits: try values.decode(Int.self, forKey: .retainedUnits),
      retainedInputUnits: try values.decodeIfPresent(Int.self, forKey: .retainedInputUnits),
      scoringUnitBasis: try values.decodeIfPresent(ResultScoringUnitBasis.self, forKey: .scoringUnitBasis))
    // Genuine v1 local records retain their original counts and values. New
    // metadata cannot be disguised as that old contract, even in archives.
    if version == 1, retainedInputUnits == nil, scoringUnitBasis == nil { return }
    guard version == 2, totalAttempts >= 0, (0...totalAttempts).contains(correctAttempts),
      let input = retainedInputUnits, (0...totalAttempts).contains(input),
      retainedUnits >= input, (0...retainedUnits).contains(creditedUnits), let basis = scoringUnitBasis
    else { throw Self.invalid(decoder) }
    switch basis {
    case .utf16:
      guard retainedUnits == input else { throw Self.invalid(decoder) }
    case .koreanJamo:
      let maximum = input.multipliedReportingOverflow(by: 5)
      guard !maximum.overflow, retainedUnits <= maximum.partialValue else { throw Self.invalid(decoder) }
    }
  }

  private static func invalid(_ decoder: Decoder) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath,
      debugDescription: "Versioned input metrics require an explicit, bounded scoring basis."))
  }

  func publicationVersion(nativeCharacterCount: Int) -> Int {
    version == 1 && retainedUnits < nativeCharacterCount ? 2 : version
  }

  var versionTwoProjection: Self {
    // v1 already defines UTF-16 counts. Adapt its wire contract without
    // recalculating or rewriting any stored legacy counters or score.
    version == 1 ? .init(version: 2, correctAttempts: correctAttempts, totalAttempts: totalAttempts,
      creditedUnits: creditedUnits, retainedUnits: retainedUnits,
      retainedInputUnits: retainedUnits, scoringUnitBasis: .utf16) : self
  }
}

enum ResultInputMetricsPublicationPolicy {
  static func validate(_ result: CompletedTestResult, capabilities: RemoteServiceCapabilities?) throws {
    guard let metrics = result.inputMetrics else { return }
    let required = metrics.publicationVersion(nativeCharacterCount: result.typedCharacterCount)
    if required == 1 { return }
    guard required == 2, capabilities?.supportsResultInputMetricsV2 == true else {
      throw RemoteAccountError.serverMessage("当前服务不支持 v2 计分指标。请先升级自建服务；本机成绩不受影响。")
    }
  }
}
