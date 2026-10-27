import Foundation

enum WebsiteTestSettingsShare {
  enum Field: Int, CaseIterable, Hashable {
    case mode, parameter, customText, punctuation, numbers, language, difficulty, funbox
    var title: String {
      switch self {
      case .mode: "模式"; case .parameter: "时间／字数／引语编号"; case .customText: "自定义文本"
      case .punctuation: "标点"; case .numbers: "数字"; case .language: "语言"
      case .difficulty: "难度"; case .funbox: "趣味模式"
      }
    }
    func isVisible(mode: String?) -> Bool {
      switch self {
      case .parameter: mode != "custom" && mode != "zen"
      case .customText: mode == "custom"
      case .punctuation, .numbers, .language, .difficulty: mode != "zen"
      case .mode, .funbox: true
      }
    }
    var requiresModeSelection: Bool { self == .parameter || self == .customText }
  }
  struct Snapshot {
    let runtime: [String: WebsiteConfigValue]
    var customText: WebsiteConfigValue?
    var quoteID: Int?
    var hasUnmappedQuote = false
  }
  enum Failure: Error, LocalizedError {
    case unavailable, tooLarge, unmappedQuote
    var errorDescription: String? {
      switch self {
      case .unavailable: "当前分享内容不可用，请重新选择。"
      case .tooLarge: "自定义文本超过链接的本机处理范围，请缩短文本后再分享。"
      case .unmappedQuote: "当前引语是 Typebar 独立内容；请使用完整测试链接保留这条引语。"
      }
    }
  }
  static func link(_ snapshot: Snapshot, selected: Set<Field>, origin: String = "typebar://test") throws -> String {
    var values = Array(repeating: WebsiteConfigValue.null, count: 8)
    for field in selected {
      let value: WebsiteConfigValue
      switch field {
      case .parameter:
        switch snapshot.runtime["mode"] {
        case .string("time"), .string("words"):
          let key = snapshot.runtime["mode"] == .string("time") ? "time" : "words"
          guard case .number(let number) = snapshot.runtime[key] else { throw Failure.unavailable }
          value = .string(WebsiteNumberText.decimal(number))
        case .string("custom"): value = .string("custom")
        case .string("zen"): value = .string("zen")
        case .string("quote"):
          guard !snapshot.hasUnmappedQuote else { throw Failure.unmappedQuote }
          value = .string(String(snapshot.quoteID ?? -1))
        default: throw Failure.unavailable
        }
      case .customText:
        guard let custom = snapshot.customText else { throw Failure.unavailable }
        value = custom
      default:
        let key: String
        switch field {
        case .mode: key = "mode"; case .punctuation: key = "punctuation"; case .numbers: key = "numbers"
        case .language: key = "language"; case .difficulty: key = "difficulty"; case .funbox: key = "funbox"
        default: throw Failure.unavailable
        }
        guard let current = snapshot.runtime[key] else { throw Failure.unavailable }
        value = current
      }
      values[field.rawValue] = value
    }
    let json = WebsiteConfigJSONWriter.write(.array(values), asciiOnly: false)
    guard let compressed = URICompressedPayload.compress(json) else { throw Failure.tooLarge }
    return origin + "?testSettings=" + compressed
  }

  /// The independent custom source is read even while an ordinary mode is
  /// selected. It is never replaced by the current generated/displayed prompt.
  static func customText(in scope: WebsiteConfigSessionBuilder.Scope) -> WebsiteConfigValue? {
    guard !scope.customTextRecoveryBlocked else { return nil }
    let pipe = scope.customPipeDelimiter ?? (scope.customCompletion == .sections)
    let pieces: [String]
    if scope.customCompletion == .finish, !pipe, let wholeSource = scope.finiteTextSource {
      pieces = CustomSectionWordStream.sourceSections(from: wholeSource, usesPipe: false,
        preservesSourceSpelling: scope.customTextIsPrepared)
    } else {
      pieces = scope.preparedCustomSections ?? CustomSectionWordStream.sourceSections(
        from: scope.customText, usesPipe: pipe, preservesSourceSpelling: scope.customTextIsPrepared)
    }
    guard !pieces.isEmpty else { return nil }
    let limitMode: String, limit: Double
    switch scope.customCompletion {
    case .time: limitMode = "time"; limit = scope.customDurationOverride ?? Double(scope.parameterMemory.customTextDuration)
    case .words: limitMode = "word"; limit = Double(scope.parameterMemory.customTextWordLimit)
    case .sections: limitMode = "section"; limit = Double(scope.parameterMemory.customTextSectionLimit)
    case .finish: limitMode = pipe ? "section" : "word"; limit = Double(pieces.count)
    }
    let ordering = scope.customOrdering == .inOrder ? "repeat" : scope.customOrdering == .shuffled ? "shuffle" : "random"
    return .object(["text": .array(pieces.map(WebsiteConfigValue.string)), "mode": .string(ordering),
      "limit": .object(["value": .number(limit), "mode": .string(limitMode)]), "pipeDelimiter": .bool(pipe)])
  }

  /// Selection-only capture for an already published whole-profile practice.
  /// The legacy page's settings snapshot is a different owner and must not be
  /// attached to this configuration before the native link validates it.
  static func nativeSelection(configuration: TestConfiguration,
    scope: WebsiteConfigSessionBuilder.Scope, quote: OfflineQuote?) -> SavedTestPreset {
    let custom: String?
    if configuration.mode != .custom { custom = nil }
    else if configuration.customTextCompletion == .finish, !configuration.usesCustomTextPipeDelimiter,
      let whole = scope.finiteTextSource { custom = whole }
    else if let sections = scope.preparedCustomSections {
      let candidate = sections.joined(separator: configuration.usesCustomTextPipeDelimiter ? "|" : " ")
      let restored = CustomSectionWordStream.sourceSections(from: candidate,
        usesPipe: configuration.usesCustomTextPipeDelimiter)
      let exact = restored.count == sections.count && zip(restored, sections).allSatisfy { InputTextIdentity.matches($0, $1) }
      // The old native string format cannot express literal delimiters,
      // blank prepared sections or a spelling that its editor normalizes.
      custom = exact ? candidate : nil
    } else { custom = scope.customText }
    return .init(configuration: configuration, quoteID: configuration.mode == .quote ? quote?.id : nil, customText: custom)
  }
}
