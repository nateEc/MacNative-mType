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
    if let timing = result.terminalTiming, !timing.isValid(wallClockDuration: result.wallClockDuration,
      mode: result.configuration.mode, outcome: result.outcome) {
      throw RemoteAccountError.serverMessage("结束计时证据无效，不能发布此成绩。")
    }
    guard result.terminalTiming == nil || capabilities?.supportsResultTerminalTiming == true else {
      throw RemoteAccountError.serverMessage("当前服务不支持结束计时证据。请先升级自建服务；本机成绩不受影响。")
    }
    guard result.terminalTiming == nil || result.configuration.mode == .zen else {
      throw RemoteAccountError.serverMessage("普通 BailOut 的保存资格尚未完成兼容，暂不能发布此成绩。")
    }
    var metrics: RemoteResultConsistency?
    if capabilities?.supportsResultConsistency == true {
      let input = try ResultWPMConsistencyInput(prompt: result.prompt, events: result.replayEvents,
        duration: result.chartDuration, configuration: result.configuration,
        targetWordDirectory: result.targetWordDirectory, sourceScoringBasis: result.characterStats.sourceUnitBasis)
      let wpm = await input.value(calculation: calculation)
      try Task.checkCancellation()
      metrics = .init(version: 1, keyConsistency: ResultConsistencyPolicy.metrics(
        events: result.replayEvents, duration: result.chartDuration,
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
