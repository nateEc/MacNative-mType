import Foundation

/// Anonymous completion metadata. Only keyConsistency belongs to history;
/// wpmConsistency is transient, matching the pinned source DB projection.
struct RemoteResultConsistency: Codable, Equatable, Sendable {
  let version: Int
  let keyConsistency: Double
  let wpmConsistency: Double?
}

enum ResultConsistencyPublication {
  @MainActor static func prepare(
    result: CompletedTestResult, capabilities: RemoteServiceCapabilities?,
    calculation: @escaping @Sendable (ResultWPMConsistencyInput) async -> Double? = { $0.calculate() }
  ) async throws -> RemoteResultSubmission {
    try Task.checkCancellation()
    var metrics: RemoteResultConsistency?
    if capabilities?.supportsResultConsistency == true {
      let input = try ResultWPMConsistencyInput(prompt: result.prompt, events: result.replayEvents,
        duration: result.elapsedDuration, configuration: result.configuration,
        targetWordDirectory: result.targetWordDirectory, sourceScoringBasis: result.characterStats.sourceUnitBasis)
      let wpm = await input.value(calculation: calculation)
      try Task.checkCancellation()
      metrics = .init(version: 1, keyConsistency: ResultConsistencyPolicy.metrics(
        events: result.replayEvents, duration: result.elapsedDuration,
        configuration: result.configuration, keySpacingSamples: result.keySpacingSamples).key,
        wpmConsistency: wpm)
    }
    return RemoteResultSubmission(result: result,
      includesTimingEvidence: capabilities?.supportsResultTimingEvidence == true,
      includesPracticeTiming: capabilities?.supportsResultPracticeTiming == true,
      includesInputMetrics: capabilities?.supportsResultInputMetrics == true,
      includesInputMetricsV2: capabilities?.supportsResultInputMetricsV2 == true,
      resultConsistency: metrics)
  }
}
