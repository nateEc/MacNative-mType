import Foundation

enum WebsiteConfigNativeTestParametersError: Error, Equatable {
  case missingField(String), invalidField(String), unrepresentableField(String)
}

/// Final-runtime parameter draft. The independent custom-text state is supplied
/// by the caller; constructing this draft does not generate content or restart.
struct WebsiteConfigNativeTestParameters {
  static let mappedKeys: Set<String> = ["mode", "time", "words", "language", "punctuation", "numbers"]

  let mode: TestMode
  let duration: Int
  let wordLimit: Int
  let language: TypingLanguage
  let contentOptions: ContentOptions

  private static let schema = WebsiteConfigSchema(catalogs: .init(
    languages: Set(WebsiteLanguageIdentity.byWebsiteName.keys), themes: [], layouts: [], fonts: [], funboxes: []))

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativeTestParametersError.missingField(key) }
      guard Self.schema.accepts(value, for: key) else { throw WebsiteConfigNativeTestParametersError.invalidField(key) }
      return value
    }
    func text(_ key: String) throws -> String {
      guard case .string(let text) = try value(key) else { throw WebsiteConfigNativeTestParametersError.invalidField(key) }
      return text
    }
    func flag(_ key: String) throws -> Bool {
      guard case .bool(let flag) = try value(key) else { throw WebsiteConfigNativeTestParametersError.invalidField(key) }
      return flag
    }
    func count(_ key: String) throws -> Int {
      guard case .number(let number) = try value(key) else { throw WebsiteConfigNativeTestParametersError.invalidField(key) }
      guard number <= Double(OfficialTestLimitInput.maximumValue) else {
        throw WebsiteConfigNativeTestParametersError.unrepresentableField(key)
      }
      // The native limit domain is integral. Both zero signs mean an infinite
      // test, and the website's own JSON export also serializes either as 0.
      return Int(number)
    }
    guard let mode = try TestMode(rawValue: text("mode")) else { throw WebsiteConfigNativeTestParametersError.invalidField("mode") }
    self.mode = mode
    duration = try count("time")
    wordLimit = try count("words")
    guard let language = try WebsiteLanguageIdentity.language(for: text("language")) else {
      throw WebsiteConfigNativeTestParametersError.invalidField("language")
    }
    self.language = language
    contentOptions = try ContentOptions(includePunctuation: flag("punctuation"), includeNumbers: flag("numbers"))
    if mode == .quote {
      if contentOptions.includePunctuation { throw WebsiteConfigNativeTestParametersError.invalidField("punctuation") }
      if contentOptions.includeNumbers { throw WebsiteConfigNativeTestParametersError.invalidField("numbers") }
    }
  }

  func parameterMemory(preserving memory: TypebarTestParameterMemory) -> TypebarTestParameterMemory {
    .init(duration: duration, wordLimit: wordLimit, customTextDuration: memory.customTextDuration,
      customTextWordLimit: memory.customTextWordLimit, customTextSectionLimit: memory.customTextSectionLimit)
  }

  func applying(to configuration: TestConfiguration, parameterMemory: TypebarTestParameterMemory) -> TestConfiguration {
    var result = configuration
    result.mode = mode
    result.language = language
    result = result.with(polyglotBaseLanguage: nil)
    result.contentOptions = contentOptions
    result.duration = nil
    result.wordLimit = nil
    switch mode {
    case .time: result.duration = Double(duration)
    case .words: result.wordLimit = wordLimit
    case .quote, .zen: break
    case .custom:
      switch result.customTextCompletion {
      case .finish: break
      case .time: result.duration = Double(parameterMemory.customTextDuration)
      case .words: result.wordLimit = parameterMemory.customTextWordLimit
      case .sections: result.customTextSectionLimit = parameterMemory.customTextSectionLimit
      }
    }
    return result
  }
}
