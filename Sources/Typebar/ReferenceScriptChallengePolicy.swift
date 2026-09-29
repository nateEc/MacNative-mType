import CryptoKit
import Foundation

/// Only public challenge identities and content fingerprints are bundled.
/// The original script text must come from a file the user provides.
enum ReferenceScriptChallengePolicy {
  static let maximumImportedBytes = 1_000_000

  struct Specification: Codable, Equatable {
    let legacyName: String
    let fileName: String
    let byteCount: Int
    let normalizedCharacterCount: Int
    let normalizedSHA256: String
  }

  struct VerifiedScript {
    let text: String
    let specification: Specification

    fileprivate init(text: String, specification: Specification) {
      self.text = text
      self.specification = specification
    }
  }

  enum ImportError: LocalizedError, Equatable {
    case tooLarge, invalidEncoding, contentMismatch

    var errorDescription: String? {
      switch self {
      case .tooLarge: "脚本文件不能超过 1 MB。"
      case .invalidEncoding: "脚本必须是 UTF-8 纯文本。"
      case .contentMismatch: "这份文件与所选挑战的固定版本脚本不一致。"
      }
    }
  }

  static let specifications: [Specification] = [
    .init(legacyName: "inAGalaxyFarFarAway", fileName: "episode4.txt", byteCount: 61_458,
      normalizedCharacterCount: 61_458,
      normalizedSHA256: "50e636ecfc39e2b17d18e91a1b28f8051f7f5fa3d10eb73404cbbc789ade5cca"),
    .init(legacyName: "whosYourDaddy", fileName: "episode5.txt", byteCount: 42_065,
      normalizedCharacterCount: 41_803,
      normalizedSHA256: "ae5c812762c64a36829dedc95403e35322252c744dc0966237f77ccb20db2a9d"),
    .init(legacyName: "itsATrap", fileName: "episode6.txt", byteCount: 37_171,
      normalizedCharacterCount: 37_114,
      normalizedSHA256: "651deb9ca80850410e4efb0219f3e397032af23cb735d35c44719db849175078"),
    .init(legacyName: "gottaCatchEmAll", fileName: "pokemon.txt", byteCount: 6_846,
      normalizedCharacterCount: 6_844,
      normalizedSHA256: "fcdb18af2956d5724cfeb40edb036e9eaab4e7d4a2f92d3b163b6fefc60b5de4"),
    .init(legacyName: "rapGod", fileName: "rapgod.txt", byteCount: 7_855,
      normalizedCharacterCount: 7_855,
      normalizedSHA256: "391c9a7e11cad948a90337d3594ffa0839f5931296b0a8473d1316b2c3e7159b"),
    .init(legacyName: "navySeal", fileName: "navyseal.txt", byteCount: 1_516,
      normalizedCharacterCount: 1_516,
      normalizedSHA256: "65d8caf480656c763f8202ce8ff7e41846cac819038e9b5e8f568bf3a7a831c5"),
    .init(legacyName: "littleChef", fileName: "littlechef.txt", byteCount: 55_068,
      normalizedCharacterCount: 49_742,
      normalizedSHA256: "16e61fca9d2c4c0b23c04aec5d69852246d1d3a87e6dcf9be21015878094b473"),
    .init(legacyName: "crosstalk", fileName: "crosstalk.txt", byteCount: 114_778,
      normalizedCharacterCount: 113_555,
      normalizedSHA256: "3a36afc86784610e209853baaa02409bc4f25c621efc050c508f284aaf0c57f8"),
    .init(legacyName: "bees", fileName: "bees.txt", byteCount: 50_578,
      normalizedCharacterCount: 50_577,
      normalizedSHA256: "3beddcb339c0f2c941fa21f8b9bad6fd3d5639d8b43c3fc2de24fcfcfc10544a"),
    .init(legacyName: "getOffMySwamp", fileName: "shrek.txt", byteCount: 48_993,
      normalizedCharacterCount: 48_545,
      normalizedSHA256: "a345c30885ebe4ea69c87ab164b71d988e6152cccf80c1ab56398951654017dc"),
    .init(legacyName: "lookAtMeIAmTheDeveloperNow", fileName: "sourcecode.txt",
      byteCount: 798_026, normalizedCharacterCount: 600_270,
      normalizedSHA256: "103544f29db2d761c5b0131a8528f29c1ad16aa5629feb75bf7575cc48265059"),
  ]

  static func specification(for legacyName: String) -> Specification? {
    specifications.first { $0.legacyName == legacyName }
  }

  static func verifiedText(_ data: Data, for specification: Specification) throws -> String {
    guard data.count <= maximumImportedBytes else { throw ImportError.tooLarge }
    guard let source = String(data: data, encoding: .utf8) else {
      throw ImportError.invalidEncoding
    }
    let text = normalizedText(source)
    guard text.unicodeScalars.count == specification.normalizedCharacterCount else {
      throw ImportError.contentMismatch
    }
    let digest = SHA256.hash(data: Data(text.utf8))
      .map { String(format: "%02x", $0) }.joined()
    guard digest == specification.normalizedSHA256 else {
      throw ImportError.contentMismatch
    }
    return text
  }

  static func verifiedScript(_ data: Data, for specification: Specification) throws -> VerifiedScript {
    try .init(text: verifiedText(data, for: specification), specification: specification)
  }

  static func verifiedScript(at url: URL, for specification: Specification) throws -> VerifiedScript {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size > maximumImportedBytes
    {
      throw ImportError.tooLarge
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while data.count <= maximumImportedBytes {
      let amount = min(64_000, maximumImportedBytes + 1 - data.count)
      let chunk = try handle.read(upToCount: amount) ?? Data()
      if chunk.isEmpty { break }
      data.append(chunk)
    }
    return try verifiedScript(data, for: specification)
  }

  static func matchesNormalizedPrompt(_ prompt: String, for specification: Specification) -> Bool {
    guard prompt.unicodeScalars.count == specification.normalizedCharacterCount,
      normalizedText(prompt) == prompt
    else { return false }
    let digest = SHA256.hash(data: Data(prompt.utf8))
      .map { String(format: "%02x", $0) }.joined()
    return digest == specification.normalizedSHA256
  }

  /// Matches the fixed web loader: trim, replace CR/LF/TAB/space with a
  /// space, then collapse adjacent spaces. No script prose is embedded here.
  static func normalizedText(_ source: String) -> String {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    var output = String()
    output.reserveCapacity(trimmed.utf8.count)
    var previousWasSpace = false
    for scalar in trimmed.unicodeScalars {
      let value = scalar.value
      if value == 32 || value == 9 || value == 10 || value == 13 {
        if !previousWasSpace { output.append(" ") }
        previousWasSpace = true
      } else {
        output.unicodeScalars.append(scalar)
        previousWasSpace = false
      }
    }
    return output
  }
}
