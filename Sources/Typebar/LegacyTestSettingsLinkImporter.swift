import Foundation

/// Imports the historical public test-settings URL payload locally. The URL's
/// host is transport only: this importer never resolves it or performs I/O.
enum LegacyTestSettingsLinkImporter {
  /// Current Mac-only custom-text state that can complete a mode-only legacy
  /// link without treating the link as a source of text it does not contain.
  struct CustomTextFallback {
    let text: String
    let completion: CustomTextCompletion
    let duration: TimeInterval?
    let wordLimit: Int?
    let sectionLimit: Int?
    let ordering: CustomTextOrdering
  }

  enum ImportError: Error, Equatable, LocalizedError {
    case invalidLink
    case invalidPayload
    case unsupportedSetting

    var errorDescription: String? {
      switch self {
      case .invalidLink: "这不是有效的网页测试设置链接。"
      case .invalidPayload: "测试设置链接的数据无法读取。"
      case .unsupportedSetting: "测试设置链接包含此 Mac 不能安全导入的设置。"
      }
    }
  }

  private enum Mode2 {
    case count(Int)
    case keyword
  }

  private struct CustomTextSettings {
    let text: String
    let completion: CustomTextCompletion
    let duration: TimeInterval?
    let wordLimit: Int?
    let sectionLimit: Int?
    let ordering: CustomTextOrdering
  }

  private struct Payload {
    let mode: TestMode?
    let mode2: Mode2?
    let customText: CustomTextSettings?
    let punctuation: Bool?
    let numbers: Bool?
    let language: TypingLanguage?
    let difficulty: Difficulty?
    let modifiers: [TestModifier]?
    let requestsMixedLanguage: Bool
  }

  private static let maximumURLLength = 32_768
  private static let maximumCompressedPayloadLength = 32_768
  private static let fallbackDuration: TimeInterval = 30
  private static let fallbackWordLimit = 25

  static func preset(
    from link: String, current: SavedTestPreset, customTextFallback: CustomTextFallback? = nil
  ) throws -> SavedTestPreset {
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count <= maximumURLLength,
          let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          components.host != nil,
          let compressed = components.queryItems?.first(where: { $0.name == "testSettings" })?.value,
          !compressed.isEmpty,
          compressed.count <= maximumCompressedPayloadLength,
          let json = URICompressedPayload.decompress(compressed),
          let data = json.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
          array.count == 8
    else { throw ImportError.invalidLink }

    let payload = try parse(array, current: current)
    return try apply(payload, to: current, customTextFallback: customTextFallback)
  }

  private static func parse(_ values: [Any], current: SavedTestPreset) throws -> Payload {
    let mode = try parseMode(values[0])
    let mode2 = try parseMode2(values[1])
    let customText = try parseCustomText(values[2], current: current)
    let punctuation = try parseBoolean(values[3])
    let numbers = try parseBoolean(values[4])
    let language = try parseLanguage(values[5])
    let difficulty = try parseDifficulty(values[6])
    let funbox = try parseFunbox(values[7])
    return .init(
      mode: mode, mode2: mode2, customText: customText, punctuation: punctuation,
      numbers: numbers, language: language, difficulty: difficulty,
      modifiers: funbox.modifiers, requestsMixedLanguage: funbox.requestsMixedLanguage)
  }

  private static func apply(
    _ payload: Payload, to current: SavedTestPreset, customTextFallback: CustomTextFallback?
  ) throws -> SavedTestPreset {
    let old = current.configuration
    let mode = payload.mode ?? old.mode
    var duration = old.duration
    var wordLimit = old.wordLimit
    var quoteLength = old.quoteLength
    var quoteLengths = old.quoteLengths
    var quoteSelectionMode = old.quoteSelectionMode
    var customTextCompletion = old.customTextCompletion
    var customTextSectionLimit = old.customTextSectionLimit
    var customTextOrdering = old.customTextOrdering
    var language = payload.language ?? old.language
    var customText = current.customText
    var quoteID = mode == .quote ? current.quoteID : nil

    if let custom = payload.customText {
      customText = custom.text
      if mode == .custom {
        customTextCompletion = custom.completion
        customTextSectionLimit = custom.sectionLimit
        customTextOrdering = custom.ordering
        duration = custom.duration
        wordLimit = custom.wordLimit
      }
    }

    if payload.customText == nil, mode == .custom, let customTextFallback {
      guard CustomTextPolicy.isValid(customTextFallback.text) else {
        throw ImportError.unsupportedSetting
      }
      customText = customTextFallback.text
      customTextCompletion = customTextFallback.completion
      customTextSectionLimit = customTextFallback.sectionLimit
      customTextOrdering = customTextFallback.ordering
      duration = customTextFallback.duration
      wordLimit = customTextFallback.wordLimit
    }

    if payload.requestsMixedLanguage {
      language = .mixedLanguages
    }

    let importedCount = payload.mode2.flatMap { count(from: $0) }

    switch mode {
    case .time:
      duration = importedCount.map(TimeInterval.init)
        ?? (old.mode == .time ? old.duration : nil)
        ?? fallbackDuration
      wordLimit = nil
    case .words:
      wordLimit = importedCount
        ?? (old.mode == .words ? old.wordLimit : nil)
        ?? fallbackWordLimit
      duration = nil
    case .quote:
      duration = nil
      wordLimit = nil
      if importedCount != nil {
        // External quote IDs do not identify Typebar-owned quote content.
        // Clearing the selection lets the app choose a local quote instead.
        quoteID = nil
        quoteLength = .all
        quoteLengths = nil
        quoteSelectionMode = .lengths
      }
    case .zen:
      duration = nil
      wordLimit = nil
    case .custom:
      guard let text = customText, CustomTextPolicy.isValid(text) else {
        // A partial mode-only link has no portable source text. Its caller can
        // supply its current text through `current` to keep this import local.
        throw ImportError.unsupportedSetting
      }
      if payload.customText == nil, customTextFallback != nil {
        switch customTextCompletion {
        case .finish:
          duration = nil
          wordLimit = nil
          customTextSectionLimit = nil
        case .time:
          duration = duration ?? fallbackDuration
          wordLimit = nil
          customTextSectionLimit = nil
        case .words:
          duration = nil
          wordLimit = wordLimit ?? fallbackWordLimit
          customTextSectionLimit = nil
        case .sections:
          duration = nil
          wordLimit = nil
          customTextSectionLimit = min(
            customTextSectionLimit ?? 1, max(1, CustomTextPolicy.sections(in: text).count))
        }
      } else if payload.customText == nil {
        switch customTextCompletion {
        case .finish:
          duration = nil
          wordLimit = nil
          customTextSectionLimit = nil
        case .time:
          duration = old.mode == .custom ? old.duration : fallbackDuration
          wordLimit = nil
          customTextSectionLimit = nil
        case .words:
          duration = nil
          wordLimit = old.mode == .custom ? old.wordLimit : fallbackWordLimit
          customTextSectionLimit = nil
        case .sections:
          duration = nil
          wordLimit = nil
          customTextSectionLimit = min(
            old.customTextSectionLimit ?? 1, max(1, CustomTextPolicy.sections(in: text).count))
        }
      }
    }

    var options = old.contentOptions
    if let punctuation = payload.punctuation { options.includePunctuation = punctuation }
    if let numbers = payload.numbers { options.includeNumbers = numbers }

    let modifiers = payload.modifiers ?? old.modifiers
    let configuration = TestConfiguration(
      mode: mode, duration: duration, wordLimit: wordLimit,
      difficulty: payload.difficulty ?? old.difficulty, rules: old.rules, language: language,
      englishVariant: old.englishVariant, quoteLength: quoteLength, quoteLengths: quoteLengths,
      quoteSelectionMode: quoteSelectionMode, customTextCompletion: customTextCompletion,
      customTextSectionLimit: customTextSectionLimit, customTextOrdering: customTextOrdering,
      mixedLanguageComponents: old.mixedLanguageComponents, modifiers: modifiers,
      contentOptions: options, challengeID: nil)
    return .init(configuration: configuration, quoteID: quoteID, customText: customText)
  }

  private static func parseMode(_ value: Any) throws -> TestMode? {
    if value is NSNull { return nil }
    guard let raw = value as? String, let mode = TestMode(rawValue: raw) else {
      throw ImportError.unsupportedSetting
    }
    return mode
  }

  private static func parseMode2(_ value: Any) throws -> Mode2? {
    if value is NSNull { return nil }
    if let raw = value as? String {
      if raw == "zen" || raw == "custom" { return .keyword }
      guard let count = nonnegativeSafeInteger(raw) else { throw ImportError.unsupportedSetting }
      return .count(count)
    }
    guard !(value is Bool), let number = value as? NSNumber else {
      throw ImportError.unsupportedSetting
    }
    let decimal = number.doubleValue
    guard decimal.isFinite, decimal >= 0, decimal <= Double(OfficialTestLimitInput.maximumValue) else {
      throw ImportError.unsupportedSetting
    }
    return .count(Int(decimal.rounded(.towardZero)))
  }

  private static func parseBoolean(_ value: Any) throws -> Bool? {
    if value is NSNull { return nil }
    guard let value = value as? Bool else { throw ImportError.unsupportedSetting }
    return value
  }

  private static func parseLanguage(_ value: Any) throws -> TypingLanguage? {
    if value is NSNull { return nil }
    guard let raw = value as? String, let language = TypingLanguage(rawValue: raw) else {
      throw ImportError.unsupportedSetting
    }
    return language
  }

  private static func parseDifficulty(_ value: Any) throws -> Difficulty? {
    if value is NSNull { return nil }
    guard let raw = value as? String, let difficulty = Difficulty(rawValue: raw) else {
      throw ImportError.unsupportedSetting
    }
    return difficulty
  }

  private static func parseFunbox(_ value: Any) throws -> (
    modifiers: [TestModifier]?, requestsMixedLanguage: Bool
  ) {
    if value is NSNull { return (nil, false) }
    let names: [String]
    if let legacy = value as? String {
      names = legacy.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
    } else if let items = value as? [Any] {
      guard items.count <= 15, let values = items as? [String] else {
        throw ImportError.unsupportedSetting
      }
      names = values
    } else {
      throw ImportError.unsupportedSetting
    }
    guard names.count <= 15, !names.contains(where: \.isEmpty) else {
      throw ImportError.unsupportedSetting
    }

    var modifiers: [TestModifier] = []
    var requestsMixedLanguage = false
    for name in names {
      guard let target = FunboxCommandCatalog.target(for: "funbox.changeFunbox\(name)") else {
        throw ImportError.unsupportedSetting
      }
      switch target {
      case .modifier(let modifier):
        if !modifiers.contains(modifier) { modifiers.append(modifier) }
      case .polyglot:
        requestsMixedLanguage = true
      case .clear:
        throw ImportError.unsupportedSetting
      }
    }
    return (modifiers, requestsMixedLanguage)
  }

  private static func parseCustomText(
    _ value: Any, current: SavedTestPreset
  ) throws -> CustomTextSettings? {
    if value is NSNull { return nil }
    guard let object = value as? [String: Any],
          let rawText = object["text"] as? [Any],
          !rawText.isEmpty,
          let pieces = rawText as? [String]
    else { throw ImportError.unsupportedSetting }

    let currentUsesSections = current.configuration.customTextCompletion == .sections
    let providedPipe = try optionalBoolean(object["pipeDelimiter"])
    let legacyDelimiter = try optionalString(object["delimiter"])
    let usesPipe = currentUsesSections || providedPipe == true || legacyDelimiter == "|"
    let text = pieces.joined(separator: usesPipe ? "|" : " ")
    guard CustomTextPolicy.isValid(text) else { throw ImportError.unsupportedSetting }

    let ordering = try customTextOrdering(object["mode"])
    let limit = try customTextLimit(object, text: text, usesPipe: usesPipe, current: current)
    return .init(
      text: text, completion: limit.completion, duration: limit.duration,
      wordLimit: limit.wordLimit, sectionLimit: limit.sectionLimit, ordering: ordering)
  }

  private static func customTextOrdering(_ value: Any?) throws -> CustomTextOrdering {
    guard let value else { return .inOrder }
    guard let raw = value as? String else { throw ImportError.unsupportedSetting }
    switch raw {
    case "repeat": return .inOrder
    case "shuffle": return .shuffled
    case "random": return .random
    default: throw ImportError.unsupportedSetting
    }
  }

  private static func customTextLimit(
    _ object: [String: Any], text: String, usesPipe: Bool, current: SavedTestPreset
  ) throws -> (
    completion: CustomTextCompletion, duration: TimeInterval?, wordLimit: Int?, sectionLimit: Int?
  ) {
    if let rawLimit = object["limit"] {
      guard let limit = rawLimit as? [String: Any],
            let mode = limit["mode"] as? String,
            let rawValue = limit["value"],
            let value = try nonnegativeSafeInteger(rawValue)
      else { throw ImportError.unsupportedSetting }
      return try customTextLimit(mode: mode, value: value, text: text)
    }

    let isWordRandom = try optionalBoolean(object["isWordRandom"]) ?? false
    let isTimeRandom = try optionalBoolean(object["isTimeRandom"]) ?? false
    let legacyWord = try optionalNonnegativeSafeInteger(object["word"])
    let legacyTime = try optionalNonnegativeSafeInteger(object["time"])
    if isWordRandom || legacyWord != nil {
      return try customTextLimit(mode: "word", value: legacyWord ?? textPieceCount(text, usesPipe: usesPipe), text: text)
    }
    if isTimeRandom || legacyTime != nil {
      return try customTextLimit(mode: "time", value: legacyTime ?? textPieceCount(text, usesPipe: usesPipe), text: text)
    }

    switch current.configuration.customTextCompletion {
    case .finish:
      return (.finish, nil, nil, nil)
    case .time:
      return (.time, TimeInterval(textPieceCount(text, usesPipe: usesPipe)), nil, nil)
    case .words:
      return (.words, nil, textPieceCount(text, usesPipe: usesPipe), nil)
    case .sections:
      let count = CustomTextPolicy.sections(in: text).count
      return (.sections, nil, nil, max(1, count))
    }
  }

  private static func customTextLimit(
    mode: String, value: Int, text: String
  ) throws -> (completion: CustomTextCompletion, duration: TimeInterval?, wordLimit: Int?, sectionLimit: Int?) {
    switch mode {
    case "time": return (.time, TimeInterval(value), nil, nil)
    case "word": return (.words, nil, value, nil)
    case "section":
      let sections = CustomTextPolicy.sections(in: text).count
      guard (1...sections).contains(value) else { throw ImportError.unsupportedSetting }
      return (.sections, nil, nil, value)
    default: throw ImportError.unsupportedSetting
    }
  }

  private static func optionalBoolean(_ value: Any?) throws -> Bool? {
    guard let value else { return nil }
    guard let boolean = value as? Bool else { throw ImportError.unsupportedSetting }
    return boolean
  }

  private static func optionalString(_ value: Any?) throws -> String? {
    guard let value else { return nil }
    guard let string = value as? String else { throw ImportError.unsupportedSetting }
    return string
  }

  private static func optionalNonnegativeSafeInteger(_ value: Any?) throws -> Int? {
    guard let value else { return nil }
    guard let parsed = try nonnegativeSafeInteger(value) else { throw ImportError.unsupportedSetting }
    return parsed
  }

  private static func nonnegativeSafeInteger(_ value: Any) throws -> Int? {
    guard !(value is Bool), let number = value as? NSNumber else { return nil }
    let decimal = number.doubleValue
    guard decimal.isFinite, decimal >= 0,
          decimal.rounded(.towardZero) == decimal,
          decimal <= Double(OfficialTestLimitInput.maximumValue)
    else { return nil }
    return Int(decimal)
  }

  private static func nonnegativeSafeInteger(_ value: String) -> Int? {
    guard !value.isEmpty, value.allSatisfy(\.isNumber), let parsed = Int(value),
          (0...OfficialTestLimitInput.maximumValue).contains(parsed)
    else { return nil }
    return parsed
  }

  private static func count(from mode2: Mode2) -> Int? {
    guard case .count(let count) = mode2 else { return nil }
    return count
  }

  private static func textPieceCount(_ text: String, usesPipe: Bool) -> Int {
    if usesPipe { return max(1, CustomTextPolicy.sections(in: text).count) }
    return max(1, text.split(whereSeparator: \.isWhitespace).count)
  }
}

/// A bounded URI-safe LZ decoder. It is deliberately decode-only because
/// Typebar's own links use its native, versioned share format.
private enum URICompressedPayload {
  private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"
  private static let lookup = Dictionary(uniqueKeysWithValues: alphabet.utf8.enumerated().map { ($0.element, $0.offset) })
  private static let maximumDecodedUTF16Length = 65_536

  static func decompress(_ input: String) -> String? {
    let bytes = Array(input.utf8)
    guard !bytes.isEmpty, let values = decodeValues(bytes) else { return nil }
    var reader = BitReader(values: values)
    var dictionary: [[UInt16]?] = [nil, nil, nil]
    var enlargeIn = 4
    var dictionarySize = 4
    var numberOfBits = 3

    guard let firstCode = reader.read(bits: 2) else { return nil }
    let first: UInt16
    switch firstCode {
    case 0:
      guard let value = reader.read(bits: 8) else { return nil }
      first = UInt16(value)
    case 1:
      guard let value = reader.read(bits: 16) else { return nil }
      first = UInt16(value)
    case 2:
      return ""
    default:
      return nil
    }

    var word = [first]
    var result = word
    dictionary.append(word)

    while true {
      guard var code = reader.read(bits: numberOfBits) else { return nil }
      switch code {
      case 0:
        guard let value = reader.read(bits: 8) else { return nil }
        dictionary.append([UInt16(value)])
        code = dictionarySize
        dictionarySize += 1
        enlargeIn -= 1
      case 1:
        guard let value = reader.read(bits: 16) else { return nil }
        dictionary.append([UInt16(value)])
        code = dictionarySize
        dictionarySize += 1
        enlargeIn -= 1
      case 2:
        return String(decoding: result, as: UTF16.self)
      default:
        break
      }

      if enlargeIn == 0 {
        enlargeIn = 1 << numberOfBits
        numberOfBits += 1
      }

      let entry: [UInt16]
      if code < dictionary.count, let stored = dictionary[code] {
        entry = stored
      } else if code == dictionarySize, let first = word.first {
        entry = word + [first]
      } else {
        return nil
      }
      guard result.count + entry.count <= maximumDecodedUTF16Length else { return nil }
      result.append(contentsOf: entry)
      guard let entryFirst = entry.first else { return nil }
      dictionary.append(word + [entryFirst])
      dictionarySize += 1
      enlargeIn -= 1
      word = entry
      if enlargeIn == 0 {
        enlargeIn = 1 << numberOfBits
        numberOfBits += 1
      }
    }
  }

  private static func decodeValues(_ bytes: [UInt8]) -> [Int]? {
    var values: [Int] = []
    values.reserveCapacity(bytes.count)
    for byte in bytes {
      // Form-style query decoding can turn the URI alphabet's `+` into a
      // space before this importer receives it.
      let normalized = byte == 0x20 ? UInt8(ascii: "+") : byte
      guard let value = lookup[normalized] else { return nil }
      values.append(value)
    }
    return values
  }

  private struct BitReader {
    let values: [Int]
    var index = 1
    var value: Int
    var position = 32
    var exhausted = false

    init(values: [Int]) {
      self.values = values
      value = values[0]
    }

    mutating func read(bits: Int) -> Int? {
      guard !exhausted else { return nil }
      var result = 0
      var power = 1
      for _ in 0..<bits {
        let current = value & position
        position >>= 1
        if position == 0 {
          position = 32
          if index < values.count {
            value = values[index]
            index += 1
          } else {
            value = 0
            exhausted = true
          }
        }
        if current != 0 { result |= power }
        power <<= 1
      }
      return result
    }
  }
}
