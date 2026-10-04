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
    try RemoteIncompletePracticePolicy.validate(result, capabilities: capabilities)
    let experienceEvidence = try RemoteExperienceEvidencePolicy.prepare(result, capabilities: capabilities)
    if let elapsedTime = result.elapsedTime, !elapsedTime.isServiceCompatible(
      mode: result.configuration.mode, bailedOut: result.outcome == .bailedOut,
      calendarSeconds: result.finishedAt.timeIntervalSince(result.startedAt)) {
      throw RemoteAccountError.serverMessage("独立时长或计时成绩日期一致性无效，不能发布；本机记录保留。")
    }
    guard result.elapsedTime == nil || capabilities?.supportsResultElapsedTime == true else {
      throw RemoteAccountError.serverMessage("当前服务不支持独立测量时长。请先升级自建服务；本机成绩不受影响。")
    }
    guard result.outcome != .bailedOut || capabilities?.supportsResultBailout == true else {
      // Timing support alone cannot authorize a completed-looking BailOut.
      throw RemoteAccountError.serverMessage("当前服务不支持 BailOut 中止成绩协议。请先升级自建服务；本机成绩不受影响。")
    }
    if let timing = result.terminalTiming, !timing.isValid(wallClockDuration: result.capturedDuration,
      mode: result.configuration.mode, outcome: result.outcome) {
      throw RemoteAccountError.serverMessage("结束计时证据无效，不能发布此成绩。")
    }
    guard result.terminalTiming == nil || capabilities?.supportsResultTerminalTiming == true else {
      throw RemoteAccountError.serverMessage("当前服务不支持结束计时证据。请先升级自建服务；本机成绩不受影响。")
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
      resultConsistency: metrics, experienceEvidence: experienceEvidence)
  }
}
