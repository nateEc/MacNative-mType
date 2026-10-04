import Foundation

enum RemoteIncompletePracticePolicy {
  static func isValid(_ evidence: ResultIncompletePractice, count: Int?,
    timing: RemoteResultPracticeTiming?) -> Bool {
    guard let count, let timing, timing.version == 1, evidence.version == 1,
      (0...RemoteResultPracticeTiming.maximumTerminalEngagedMilliseconds).contains(timing.terminalEngagedMilliseconds),
      (0...RemoteResultPracticeTiming.maximumRestartCount).contains(count),
      evidence.attempts.count == count, evidence.attempts.allSatisfy(\.isValid),
      (0...(count * RemoteResultPracticeTiming.maximumTerminalEngagedMilliseconds))
        .contains(timing.priorAttemptEngagedMilliseconds) else { return false }
    let seconds = Double(timing.priorAttemptEngagedMilliseconds) / 1_000
    let sum = evidence.summedSeconds
    guard sum.isFinite else { return false }
    if count == 0 { return seconds == 0 }
    // Each attempt is rounded to hundredths; the carried raw sum is then
    // encoded in milliseconds. Preserve both independent rounding boundaries.
    return abs(sum - seconds) <= Double(count) * 0.005 + 0.0005 + 1e-9
      + max(sum, seconds) * Double.ulpOfOne * 8
  }

  static func validate(_ result: CompletedTestResult, capabilities: RemoteServiceCapabilities?) throws {
    guard let evidence = result.incompletePractice else { return }
    guard evidence.isValid(restartCount: result.restartCount, engagedDuration: result.priorAttemptEngagedDuration),
      isValid(evidence, count: result.restartCount, timing: RemoteResultPracticeTiming(result: result)) else {
      throw RemoteAccountError.serverMessage("逐次未完成练习证据超出投稿边界或与次数／时长不符；本机记录保留。")
    }
    guard capabilities?.supportsResultIncompletePractice == true,
      capabilities?.supportsResultPracticeTiming == true else {
      throw RemoteAccountError.serverMessage("当前服务不支持逐次未完成练习证据。请先升级自建服务；本机成绩不受影响。")
    }
  }
}
