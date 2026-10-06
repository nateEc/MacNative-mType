import Vapor

/// Explicit grouping controls captured at completion, not a client PB claim.
/// Missing legacy reports remain unknown; all four fields are mandatory in v1.
public struct ResultPersonalBestConfiguration: Content, Equatable, Sendable {
  public let version: Int
  public let difficulty: String
  public let punctuation: Bool
  public let numbers: Bool
  public let lazyMode: Bool
  public var isValid: Bool { version == 1 && ["normal", "expert", "master"].contains(difficulty) }

  public init(version: Int = 1, difficulty: String, punctuation: Bool, numbers: Bool, lazyMode: Bool) {
    self.version = version; self.difficulty = difficulty; self.punctuation = punctuation
    self.numbers = numbers; self.lazyMode = lazyMode
  }
  private enum CodingKeys: String, CodingKey { case version, difficulty, punctuation, numbers, lazyMode }
  public init(from decoder: Decoder) throws {
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
