import Foundation

struct RemoteSpeedPrecision: Codable, Equatable, Sendable {
  let version: Int
  let wpm: Double
  let rawWpm: Double
  var isValid: Bool { version == 1 && Self.isCanonical(wpm) && Self.isCanonical(rawWpm) && rawWpm >= wpm }
  static func isCanonical(_ value: Double) -> Bool {
    value.isFinite && (0...420).contains(value) && abs(ResultTerminalTiming.round(value) - value) <= 1e-9
  }
  func matches(wpm: Int, rawWpm: Int) -> Bool {
    isValid && Int(self.wpm.rounded()) == wpm && Int(self.rawWpm.rounded()) == rawWpm
  }
  init(version: Int = 1, wpm: Double, rawWpm: Double) {
    self.version = version; self.wpm = wpm; self.rawWpm = rawWpm
  }
  private enum CodingKeys: String, CodingKey { case version, wpm, rawWpm }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy:CodingKeys.self)
    self.init(version:try values.decode(Int.self,forKey:.version),
      wpm:try values.decode(Double.self,forKey:.wpm),rawWpm:try values.decode(Double.self,forKey:.rawWpm))
    guard isValid else { throw DecodingError.dataCorruptedError(forKey:.wpm,in:values,
      debugDescription:"Unsupported or invalid speed precision") }
  }
}

enum RemoteSpeedPrecisionPolicy {
  static func prepare(_ result: CompletedTestResult, capabilities: RemoteServiceCapabilities?) throws -> RemoteSpeedPrecision? {
    let speed = RemoteSpeedPrecision(wpm:ResultTerminalTiming.round(result.preciseWpm),
      rawWpm:ResultTerminalTiming.round(result.preciseRawWpm))
    guard capabilities?.supportsResultSpeedPrecision == true else {
      guard speed.wpm == Double(result.wpm), speed.rawWpm == Double(result.rawWpm) else {
        throw RemoteAccountError.serverMessage("当前服务不能保存小数速度，请先升级自建服务；本机成绩保留。")
      }
      return nil
    }
    guard speed.isValid else { throw RemoteAccountError.serverMessage("精确速度必须在 0–420 WPM 内且 Raw 不低于速度；本机成绩保留。") }
    if let metrics = result.inputMetrics {
      let required = metrics.publicationVersion(nativeCharacterCount:result.typedCharacterCount)
      guard required == 1 && (capabilities?.supportsResultInputMetrics == true || capabilities?.supportsResultInputMetricsV2 == true)
        || required == 2 && capabilities?.supportsResultInputMetricsV2 == true else {
        throw RemoteAccountError.serverMessage("精确速度需要配套计分指标能力；本机成绩保留。")
      }
    }
    return speed
  }
}

enum RemoteSpeedPresentation {
  static func text(_ value: Double, precise: Bool) -> String {
    String(format:precise ? "%.2f" : "%.0f",locale:Locale(identifier:"en_US_POSIX"),value)
  }
}
