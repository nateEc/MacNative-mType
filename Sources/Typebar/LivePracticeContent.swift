import Foundation

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
    guard configuration.mode == .time || configuration.mode == .words,
      configuration.language.usesSpaceDelimitedWords
    else { return nil }
    if configuration.modifiers.contains(.poetryStream) { return .poetry }
    if configuration.modifiers.contains(.referenceStream) { return .encyclopedia }
    return nil
  }
}

struct LivePracticeContent: Equatable {
  let source: LivePracticeContentSource
  let title: String
  let byline: String?
  let text: String

  var attribution: String {
    let detail = [title, byline].compactMap { $0 }.joined(separator: " · ")
    return detail.isEmpty ? source.displayName : "\(source.displayName)：\(detail)"
  }

  func prompt(for configuration: TestConfiguration) -> String {
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return text }
    let targetCount: Int
    switch configuration.mode {
    case .time:
      targetCount = max(300, Int(ceil((configuration.duration ?? 30) / 60 * 240)))
    case .words:
      targetCount = configuration.wordLimit ?? 25
    case .quote, .zen, .custom:
      targetCount = words.count
    }
    return (0..<targetCount).map { words[$0 % words.count] }.joined(separator: " ")
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
      source: .poetry, title: first.title, byline: first.author, rawText: first.lines.joined(separator: " "))
  }

  static func encyclopedia(from data: Data) -> LivePracticeContent? {
    guard let document = try? JSONDecoder().decode(EncyclopediaSummary.self, from: data) else {
      return nil
    }
    return makeContent(source: .encyclopedia, title: document.title, byline: nil, rawText: document.extract)
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
    return encyclopedia(from: data)
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

  private static func wikipediaLanguageCode(for language: TypingLanguage) -> String {
    switch language {
    case .english, .mixedEnglishChinese, .mixedLanguages:
      return "en"
    case .spanish: return "es"
    case .german: return "de"
    case .french: return "fr"
    case .italian: return "it"
    case .portuguese: return "pt"
    case .simplifiedChinese: return "zh"
    default: return "en"
    }
  }

  private static func makeContent(
    source: LivePracticeContentSource, title: String, byline: String?, rawText: String
  ) -> LivePracticeContent? {
    let words = rawText.split(whereSeparator: { !$0.isLetter }).map(String.init)
    guard !words.isEmpty else { return nil }
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedByline = byline?.trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(
      source: source, title: normalizedTitle.isEmpty ? source.displayName : normalizedTitle,
      byline: normalizedByline?.isEmpty == false ? normalizedByline : nil,
      text: words.joined(separator: " "))
  }
}
