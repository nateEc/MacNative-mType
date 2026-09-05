import Foundation
import NaturalLanguage

/// Public content sources used by the reference product's poetry and
/// encyclopedia practice modes. Typebar requests them only after the user
/// explicitly enables the corresponding modifier, and always keeps its own
/// offline stream available as a fallback.
enum LivePracticeContentSource: Equatable {
  case poetry
  case encyclopedia

  var displayName: String {
    switch self {
    case .poetry: "诗歌内容"
    case .encyclopedia: "百科内容"
    }
  }

  static func selected(for configuration: TestConfiguration) -> Self? {
    guard configuration.mode == .time || configuration.mode == .words else { return nil }
    if configuration.modifiers.contains(.poetryStream),
      configuration.language.usesSpaceDelimitedWords
    {
      return .poetry
    }
    if configuration.modifiers.contains(.referenceStream),
      configuration.language.supportsLiveEncyclopedia
    {
      return .encyclopedia
    }
    return nil
  }
}

struct LivePracticeContent: Equatable {
  let source: LivePracticeContentSource
  let title: String
  let byline: String?
  let text: String
  private let tokens: [String]
  private let separator: String

  init(
    source: LivePracticeContentSource, title: String, byline: String?, tokens: [String],
    separator: String
  ) {
    self.source = source
    self.title = title
    self.byline = byline
    self.tokens = tokens
    self.separator = separator
    text = tokens.joined(separator: separator)
  }

  var attribution: String {
    let detail = [title, byline].compactMap { $0 }.joined(separator: " · ")
    return detail.isEmpty ? source.displayName : "\(source.displayName)：\(detail)"
  }

  func prompt(for configuration: TestConfiguration) -> String {
    guard !tokens.isEmpty else { return text }
    let targetCount: Int
    switch configuration.mode {
    case .time:
      targetCount = max(300, Int(ceil((configuration.duration ?? 30) / 60 * 240)))
    case .words:
      targetCount = configuration.wordLimit ?? 25
    case .quote, .zen, .custom:
      targetCount = tokens.count
    }
    return (0..<targetCount).map { tokens[$0 % tokens.count] }.joined(separator: separator)
  }
}

enum LivePracticeContentReplacementPolicy {
  static func shouldApply(
    hasStarted: Bool, currentConfiguration: TestConfiguration,
    requestedConfiguration: TestConfiguration
  ) -> Bool {
    !hasStarted && currentConfiguration == requestedConfiguration
  }
}

enum LivePracticeContentService {
  private struct PoetryDocument: Decodable {
    let title: String
    let author: String
    let lines: [String]
  }

  private struct EncyclopediaSummary: Decodable {
    let title: String
    let extract: String
  }

  static func fetch(
    source: LivePracticeContentSource, language: TypingLanguage
  ) async -> LivePracticeContent? {
    switch source {
    case .poetry: return await fetchPoetry()
    case .encyclopedia: return await fetchEncyclopedia(language: language)
    }
  }

  static func poetry(from data: Data) -> LivePracticeContent? {
    guard let document = try? JSONDecoder().decode([PoetryDocument].self, from: data),
      let first = document.first
    else { return nil }
    return makeContent(
      source: .poetry, title: first.title, byline: first.author, rawText: first.lines.joined(separator: " "),
      language: .english)
  }

  static func encyclopedia(
    from data: Data, language: TypingLanguage = .english
  ) -> LivePracticeContent? {
    guard let document = try? JSONDecoder().decode(EncyclopediaSummary.self, from: data) else {
      return nil
    }
    return makeContent(
      source: .encyclopedia, title: document.title, byline: nil, rawText: document.extract,
      language: language)
  }

  private static func fetchPoetry() async -> LivePracticeContent? {
    guard let url = URL(string: "https://poetrydb.org/random") else { return nil }
    guard let data = await data(from: url) else { return nil }
    return poetry(from: data)
  }

  private static func fetchEncyclopedia(language: TypingLanguage) async -> LivePracticeContent? {
    guard let url = URL(string: "https://\(wikipediaLanguageCode(for: language)).wikipedia.org/api/rest_v1/page/random/summary")
    else { return nil }
    guard let data = await data(from: url) else { return nil }
    return encyclopedia(from: data, language: language)
  }

  private static func data(from url: URL) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    request.setValue("Typebar/0.1 (native macOS typing practice)", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode)
    else { return nil }
    return data
  }

  static func wikipediaLanguageCode(for language: TypingLanguage) -> String {
    switch language {
    case .english, .mixedEnglishChinese, .mixedLanguages:
      return "en"
    case .spanish: return "es"
    case .german: return "de"
    case .afrikaans: return "af"
    case .azerbaijani: return "az"
    case .belarusian: return "be"
    case .latvian: return "lv"
    case .irish: return "ga"
    case .galician: return "gl"
    case .kurdishCentral: return "ckb"
    case .arabic: return "ar"
    case .hebrew: return "he"
    case .persian: return "fa"
    case .urdu: return "ur"
    case .tamil: return "ta"
    case .hindi: return "hi"
    case .gujarati: return "gu"
    case .bangla: return "bn"
    case .thai: return "th"
    case .nepali: return "ne"
    case .kannada: return "kn"
    case .telugu: return "te"
    case .malayalam: return "ml"
    case .sanskrit: return "sa"
    case .sinhala: return "si"
    case .khmer: return "km"
    case .myanmarBurmese: return "my"
    case .lao: return "lo"
    case .amharic: return "am"
    case .greek, .greeklish: return "el"
    case .dutch: return "nl"
    case .filipino: return "tl"
    case .catalan: return "ca"
    case .indonesian: return "id"
    case .malay: return "ms"
    case .danish: return "da"
    case .norwegianBokmal: return "no"
    case .norwegianNynorsk: return "nn"
    case .swedish: return "sv"
    case .hungarian: return "hu"
    case .czech: return "cs"
    case .slovak: return "sk"
    case .slovenian: return "sl"
    case .croatian: return "hr"
    case .serbian, .serbianLatin: return "sr"
    case .bulgarian: return "bg"
    case .romanian: return "ro"
    case .finnish: return "fi"
    case .estonian: return "et"
    case .icelandic: return "is"
    case .french: return "fr"
    case .italian: return "it"
    case .portuguese: return "pt"
    case .simplifiedChinese, .traditionalChinese: return "zh"
    case .russian: return "ru"
    case .ukrainian, .ukrainianLatin: return "uk"
    case .japaneseHiragana, .japaneseKatakana, .japaneseRomaji: return "ja"
    case .korean: return "ko"
    case .turkish: return "tr"
    case .polish: return "pl"
    default: return "en"
    }
  }

  private static func makeContent(
    source: LivePracticeContentSource, title: String, byline: String?, rawText: String,
    language: TypingLanguage
  ) -> LivePracticeContent? {
    let tokens = tokens(in: rawText, language: language)
    guard !tokens.isEmpty else { return nil }
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedByline = byline?.trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(
      source: source, title: normalizedTitle.isEmpty ? source.displayName : normalizedTitle,
      byline: normalizedByline?.isEmpty == false ? normalizedByline : nil,
      tokens: tokens, separator: language.isNoSpaceLanguage ? "" : " ")
  }

  private static func tokens(in rawText: String, language: TypingLanguage) -> [String] {
    guard language.isNoSpaceLanguage else {
      return rawText.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = rawText
    let range = rawText.startIndex..<rawText.endIndex
    var tokens: [String] = []
    tokenizer.enumerateTokens(in: range) { tokenRange, _ in
      let token = String(rawText[tokenRange])
      if token.allSatisfy(\.isLetter) { tokens.append(token) }
      return true
    }
    return tokens
  }
}

private extension TypingLanguage {
  /// Japanese native variants, Ukrainian Latin, Serbian Latin, and Greeklish are intentionally excluded:
  /// those native options promise hiragana-only, katakana-only, ASCII romaji,
  /// ASCII-Latin prompts, Serbian Latin prompts, and ASCII Greeklish prompts respectively,
  /// while a random encyclopedia extract cannot preserve that promise. Chinese
  /// source text remains directly typeable through the selected macOS IME and
  /// is segmented by the system tokenizer above.
  var supportsLiveEncyclopedia: Bool {
    self != .greeklish && self != .ukrainianLatin && self != .serbianLatin && self != .japaneseRomaji
      && (usesSpaceDelimitedWords || self == .simplifiedChinese || self == .traditionalChinese)
  }
}
