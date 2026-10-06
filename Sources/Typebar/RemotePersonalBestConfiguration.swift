import Foundation

/// The saved PB grouping controls. Language and mode2 belong to the result;
/// no score, eligibility or PB award is claimed by this projection.
struct RemotePersonalBestConfiguration: Codable, Equatable, Sendable {
  let version: Int
  let difficulty: String
  let punctuation: Bool
  let numbers: Bool
  let lazyMode: Bool
  var isValid: Bool { version == 1 && ["normal", "expert", "master"].contains(difficulty) }

  init(version: Int = 1, difficulty: String, punctuation: Bool, numbers: Bool, lazyMode: Bool) {
    self.version = version; self.difficulty = difficulty; self.punctuation = punctuation
    self.numbers = numbers; self.lazyMode = lazyMode
  }
  private enum CodingKeys: String, CodingKey { case version, difficulty, punctuation, numbers, lazyMode }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(version: try values.decode(Int.self, forKey: .version),
      difficulty: try values.decode(String.self, forKey: .difficulty),
      punctuation: try values.decode(Bool.self, forKey: .punctuation),
      numbers: try values.decode(Bool.self, forKey: .numbers),
      lazyMode: try values.decode(Bool.self, forKey: .lazyMode))
    guard isValid else { throw DecodingError.dataCorruptedError(forKey: .difficulty, in: values,
      debugDescription: "Unsupported personal best grouping configuration") }
  }
}

enum RemotePersonalBestConfigurationPolicy {
  static func prepare(_ result: CompletedTestResult, capabilities: RemoteServiceCapabilities?) throws -> RemotePersonalBestConfiguration? {
    let saved = result.configuration
    let projection = RemotePersonalBestConfiguration(difficulty: saved.difficulty.rawValue,
      punctuation: saved.contentOptions.includePunctuation, numbers: saved.contentOptions.includeNumbers,
      lazyMode: saved.modifiers.contains(.lazyLatin))
    guard capabilities?.supportsResultPersonalBestConfiguration == true else {
      guard projection.difficulty == "normal", !projection.punctuation, !projection.numbers, !projection.lazyMode else {
        throw RemoteAccountError.serverMessage("当前服务不能保存完整个人最佳配置，请先升级自建服务；本机成绩保留。")
      }
      // Absence means unknown on the service, never inferred known defaults.
      return nil
    }
    guard projection.isValid else { throw RemoteAccountError.serverMessage("个人最佳配置无效；本机成绩保留。") }
    return projection
  }
}
