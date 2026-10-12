import Foundation
import NaturalLanguage
import SwiftSoup

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

struct LivePracticePrompt: Equatable {
  let text: String
  /// Explicit source boundaries for a provider that supplies unseparated text.
  /// Live MediaWiki introductions retain their ASCII-space source fields.
  let noSpaceBoundarySource: String?
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

  var sectionDescriptor: LivePracticePrompt {
    .init(text: text, noSpaceBoundarySource: separator.isEmpty ? tokens.joined(separator: " ") : nil)
  }

  func prompt(for configuration: TestConfiguration) -> String {
    promptDescriptor(for: configuration).text
  }

  private func initialWordCount(for configuration: TestConfiguration, showAllLines: Bool) -> Int {
    if showAllLines, configuration.mode == .words, !configuration.isInfinite,
      configuration.visibleFutureWordCount == nil {
      return configuration.wordLimit ?? 25
    }
    return GeneratedPromptChunkPolicy.wordCount(for: configuration, showAllLines: showAllLines)
  }

  @MainActor func fillingInitialPrompt(
    for configuration: TestConfiguration, showAllLines: Bool,
    fetchNext: () async -> LivePracticeContent?
  ) async -> LivePracticeContent? {
    guard !Task.isCancelled else { return nil }
    guard configuration.mode == .time || configuration.mode == .words else { return self }
    // A decoded empty section is a generation failure, not failed transport.
    // Let initialization own its bounded restart rather than hiding it here.
    guard !tokens.isEmpty else { return self }
    let target = initialWordCount(for: configuration, showAllLines: showAllLines)
    // The preview budget limits presentation, not ownership of fetched text.
    // Keep each section's tail for a later larger preview or stream consumer.
    var collected = tokens
    var titles = [title]
    var authors = [byline].compactMap { $0 }
    while collected.count < target {
      guard !Task.isCancelled, let next = await fetchNext(), !Task.isCancelled,
        next.source == source, next.separator == separator
      else { return nil }
      if next.tokens.isEmpty { return next }
      collected.append(contentsOf: next.tokens)
      titles.append(next.title)
      if let author = next.byline { authors.append(author) }
    }
    return .init(source: source, title: titles.joined(separator: " / "),
      byline: authors.isEmpty ? nil : authors.joined(separator: " / "),
      tokens: collected, separator: separator)
  }

  func promptDescriptor(for configuration: TestConfiguration, showAllLines: Bool = false) -> LivePracticePrompt {
    guard !tokens.isEmpty else {
      return .init(text: text, noSpaceBoundarySource: nil)
    }
    let targetCount: Int
    switch configuration.mode {
    case .time, .words:
      targetCount = initialWordCount(for: configuration, showAllLines: showAllLines)
    case .quote, .zen, .custom:
      targetCount = tokens.count
    }
    let selectedTokens = (0..<targetCount).map { tokens[$0 % tokens.count] }
    return .init(
      text: selectedTokens.joined(separator: separator),
      noSpaceBoundarySource: separator.isEmpty ? selectedTokens.joined(separator: " ") : nil)
  }

  func continuationDescriptor(for configuration: TestConfiguration, showAllLines: Bool = false) -> LivePracticePrompt? {
    guard configuration.mode == .words || configuration.mode == .time else { return nil }
    let start = initialWordCount(for: configuration, showAllLines: showAllLines)
    let end = configuration.mode == .words && !configuration.isInfinite
      ? min(tokens.count, configuration.wordLimit ?? 25) : tokens.count
    guard start < end else { return nil }
    let remaining = tokens[start..<end]
    return .init(text: remaining.joined(separator: separator),
      noSpaceBoundarySource: separator.isEmpty ? remaining.joined(separator: " ") : nil)
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
    let author: String?
    let lines: [String]

    private enum CodingKeys: String, CodingKey { case title, author, lines }

    init(from decoder: Decoder) throws {
      let fields = try decoder.container(keyedBy: CodingKeys.self)
      lines = try fields.decode([String].self, forKey: .lines)
      // Upstream practice consumers use words only. Attribution must not
      // reject playable text; render only actual strings, never JSON coercions.
      title = (try? fields.decode(String.self, forKey: .title)) ?? ""
      author = try? fields.decode(String.self, forKey: .author)
    }
  }

  private struct PoetryResponse: Decodable {
    let first: PoetryDocument?

    init(from decoder: Decoder) throws {
      var items = try decoder.unkeyedContainer()
      // The provider selects index zero, not the first valid document. Later
      // array items are unconsumed and must not invalidate that selection.
      first = items.isAtEnd ? nil : try items.decode(PoetryDocument.self)
    }
  }

  private struct EncyclopediaSummary: Decodable {
    let title: String
    let extract: String
  }

  private struct EncyclopediaIdentity: Decodable {
    let pageid: Int
    let title: String
    let author: String?

    private enum CodingKeys: String, CodingKey { case pageid, title, author }

    init(from decoder: Decoder) throws {
      let fields = try decoder.container(keyedBy: CodingKeys.self)
      pageid = try fields.decode(Int.self, forKey: .pageid)
      // Attribution is not a prerequisite for fetching the selected page.
      // As with poetry, only actual strings are eligible for native display.
      title = (try? fields.decode(String.self, forKey: .title)) ?? ""
      author = try? fields.decode(String.self, forKey: .author)
    }
  }

  private struct EncyclopediaIntroduction: Decodable {
    struct Query: Decodable {
      struct Page: Decodable { let extract: String }
      let pages: [String: Page]
    }
    let query: Query
  }

  static func fetch(
    source: LivePracticeContentSource, language: TypingLanguage, session: URLSession = .shared
  ) async -> LivePracticeContent? {
    switch source {
    case .poetry: return await fetchPoetry(session: session)
    case .encyclopedia: return await fetchEncyclopedia(language: language, session: session)
    }
  }

  static func poetry(from data: Data) -> LivePracticeContent? {
    guard let document = try? JSONDecoder().decode(PoetryResponse.self, from: data),
      let first = document.first
    else { return nil }
    // Source words are separated by ASCII spaces within each line, not by
    // punctuation or Unicode whitespace. Count only nonempty cleaned words.
    var words: [String] = []
    for line in first.lines {
      for part in line.unicodeScalars.split(whereSeparator: { $0.value == 0x20 }) {
        let kept = part.filter { $0.value != 0x2014 && $0.value != 0x5F }
        let word = String(String.UnicodeScalarView(kept))
        guard !word.isEmpty else { continue }
        words.append(word)
        if words.count == 100 {
          return .init(source: .poetry, title: first.title, byline: first.author,
            tokens: words, separator: " ")
        }
      }
    }
    return .init(source: .poetry, title: first.title, byline: first.author,
      tokens: words, separator: " ")
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

  private static func fetchPoetry(session: URLSession) async -> LivePracticeContent? {
    guard let url = URL(string: "https://poetrydb.org/random") else { return nil }
    // Poetry classifies the decoded document, even on a non-success HTTP
    // response. Encyclopedia instead requires exactly 200 at both boundaries.
    guard let data = await data(from: url, session: session, requiresOKStatus: false) else { return nil }
    return poetry(from: data)
  }

  private static func fetchEncyclopedia(language: TypingLanguage, session: URLSession) async -> LivePracticeContent? {
    let host = "\(wikipediaLanguageCode(for: language)).wikipedia.org"
    // Empty, successfully decoded introductions select a new page. Transport
    // and schema failures still terminate; cancellation bounds obsolete work.
    while !Task.isCancelled {
      guard !Task.isCancelled,
        let url = URL(string: "https://\(host)/api/rest_v1/page/random/summary"),
        let identityData = await data(from: url, session: session),
        let identity = try? JSONDecoder().decode(EncyclopediaIdentity.self, from: identityData),
        identity.pageid > 0, !Task.isCancelled
      else { return nil }

      var introductionURL = URLComponents()
      introductionURL.scheme = "https"
      introductionURL.host = host
      introductionURL.path = "/w/api.php"
      // Parse the introduction locally without rendering or loading HTML resources.
      introductionURL.queryItems = [
        .init(name: "action", value: "query"), .init(name: "format", value: "json"),
        .init(name: "pageids", value: String(identity.pageid)),
        .init(name: "prop", value: "extracts"), .init(name: "exintro", value: "true")
      ]
      guard let url = introductionURL.url,
        let introductionData = await data(from: url, session: session), !Task.isCancelled,
        let introduction = try? JSONDecoder().decode(EncyclopediaIntroduction.self, from: introductionData),
        let page = introduction.query.pages[String(identity.pageid)]
      else { return nil }
      if let content = makeIntroductionContent(identity: identity, text: page.extract, language: language) {
        return content
      }
    }
    return nil
  }

  static func introductionText(fromHTML html: String) -> String? {
    let paragraphJoined = html.replacingOccurrences(of: #"</p><p>+"#, with: " ",
      options: .regularExpression)
    guard let document = try? SwiftSoup.parseBodyFragment(paragraphJoined),
      let body = document.body() else { return nil }
    // DOM textContent concatenates nodes, not visually laid-out block text.
    // Keep raw-text nodes inert and ignore comments/template document fragments.
    var nodes: [Node] = [body]
    var extracted = ""
    while let node = nodes.popLast() {
      if let textNode = node as? TextNode {
        extracted.append(textNode.getWholeText())
      } else if let dataNode = node as? DataNode {
        extracted.append(dataNode.getWholeData())
      } else if (node as? Element)?.tagNameNormal() != "template" {
        nodes.append(contentsOf: node.getChildNodes().reversed())
      }
    }
    return extracted
  }

  private static func makeIntroductionContent(
    identity: EncyclopediaIdentity, text: String, language: TypingLanguage
  ) -> LivePracticeContent? {
    guard let extracted = introductionText(fromHTML: text) else { return nil }
    let withoutReferences = extracted.replacingOccurrences(
      of: #"\[[0-9]+\]"#, with: "", options: .regularExpression)
    var normalized = ""
    for scalar in withoutReferences.unicodeScalars {
      switch scalar.value {
      case 0x200B...0x200D, 0xFEFF: continue
      case 0x201C, 0x201D: normalized.append("\"")
      case 0x2018, 0x2019: normalized.append("'")
      case 0x2013, 0x2014: normalized.append("-")
      case 0x2026: normalized.append("...")
      case 0x00AB: normalized.append("<<")
      case 0x00BB: normalized.append(">>")
      case 0x2007, 0x202F, 0x00A0: normalized.append(" ")
      default:
        if wikipediaLanguageCode(for: language) != "en"
          || (0x20...0x7E).contains(scalar.value) {
          normalized.unicodeScalars.append(scalar)
        }
      }
    }
    // English ASCII filtering precedes whitespace conversion in the reference.
    // Use the ECMAScript whitespace set, not Foundation's broader Unicode set.
    var spaced = ""
    for scalar in normalized.unicodeScalars {
      switch scalar.value {
      case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
        spaced.append(" ")
      default: spaced.unicodeScalars.append(scalar)
      }
    }
    let words = spaced.unicodeScalars.split(whereSeparator: { $0.value == 0x20 })
      .map { String(String.UnicodeScalarView($0)) }
    guard !words.isEmpty else { return nil }
    return .init(source: .encyclopedia,
      title: identity.title, byline: identity.author, tokens: words, separator: " ")
  }

  private static func data(
    from url: URL, session: URLSession, requiresOKStatus: Bool = true
  ) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    request.setValue("Typebar/0.1 (native macOS typing practice)", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse,
      !requiresOKStatus || http.statusCode == 200
    else { return nil }
    return data
  }

  static func wikipediaLanguageCode(for language: TypingLanguage) -> String {
    switch language {
    case .english, .english1k, .english5k, .english10k, .english25k, .english450k,
      .englishFiveLetter, .englishFiveLetter1k, .englishCommonlyMisspelled, .englishContractions,
      .englishDoubleLetter, .englishLegal, .englishMedical, .englishShakespearean,
      .oldEnglish, .pigLatin, .loremIpsum, .git, .ukrainianEndings, .ukrainianLatynkaEndings,
      .pokemon1k, .arenaStrategy, .mixedEnglishChinese, .mixedLanguages:
      return "en"
    case .kokanu: return "xxs"
    case .likanu: return "xxs"
    case .spanish, .spanish1k, .spanish10k, .spanish650k: return "es"
    case .german, .german1k, .german10k, .german250k,
      .swissGerman, .swissGerman1k, .swissGerman2k: return "de"
    case .afrikaans, .afrikaans1k, .afrikaans10k: return "af"
    case .hausa, .hausa1k: return "ha"
    case .tatar, .tatar1k, .tatar5k, .tatar9k: return "tt"
    case .tatarCrimean, .tatarCrimean1k, .tatarCrimean5k, .tatarCrimean10k,
      .tatarCrimean15k, .tatarCrimeanCyrillic, .tatarCrimeanCyrillic1k,
      .tatarCrimeanCyrillic5k, .tatarCrimeanCyrillic10k,
      .tatarCrimeanCyrillic15k: return "crh"
    case .klingon, .klingon1k: return "tlh"
    case .quenya: return "en"
    case .viossa, .viossaNjutro: return "en"
    case .maori: return "en"
    case .lojbanGismu, .lojbanCmavo: return "en"
    case .uzbek, .uzbek1k, .uzbek70k: return "uz"
    case .occitan, .occitan1k, .occitan2k, .occitan5k, .occitan10k: return "oc"
    case .oromo, .oromo1k, .oromo5k: return "om"
    case .jyutping: return "zh"
    case .bashkir: return "ba"
    case .basque: return "eu"
    case .frisian, .frisian1k: return "fy"
    case .hawaiian, .hawaiian1k: return "haw"
    case .kabyle, .kabyle1k, .kabyle2k, .kabyle5k, .kabyle10k: return "kab"
    case .maltese, .maltese1k: return "mt"
    case .xhosa, .xhosa3k: return "xh"
    case .tibetan, .tibetan1k: return "bo"
    case .kyrgyz, .kyrgyz1k: return "ky"
    case .kinyarwanda: return "rw"
    case .shona: return "en"
    case .santali: return "sat"
    case .yiddish: return "yi"
    case .friulian: return "fur"
    case .bemba, .bemba1k, .bemba10k: return "bem"
    case .azerbaijani, .azerbaijani1k: return "az"
    case .belarusian, .belarusian1k, .belarusian5k, .belarusian10k, .belarusian25k,
      .belarusian50k, .belarusian100k: return "be"
    case .belarusianLacinka: return "en"
    case .latvian, .latvian1k: return "lv"
    case .irish, .irish1k: return "ga"
    case .galician: return "gl"
    case .kurdishCentral, .kurdishCentral2k, .kurdishCentral4k: return "ckb"
    case .arabic, .arabic10k, .arabicEgypt, .arabicEgypt1k, .arabicMorocco: return "ar"
    case .pashto: return "ps"
    case .sindhi: return "sd"
    case .hebrew, .hebrew1k, .hebrew5k, .hebrew10k: return "he"
    case .persian, .persian1k, .persian5k, .persian20k, .persianRomanized: return "fa"
    case .urdu, .urdu1k, .urdu5k, .urduRoman: return "ur"
    case .urdish: return "en"
    case .tamil, .tamil1k, .tamilOld: return "ta"
    case .tanglish: return "en"
    case .hindi, .hindi1k: return "hi"
    case .hinglish: return "en"
    case .gujarati, .gujarati1k: return "gu"
    case .bangla, .bangla10k, .banglaLetters: return "bn"
    case .thai, .thai1k, .thai5k, .thai10k, .thai20k, .thai50k, .thai60k: return "th"
    case .nepali, .nepali1k: return "ne"
    case .nepaliRomanized: return "en"
    case .kannada: return "kn"
    case .telugu, .telugu1k: return "te"
    case .malayalam: return "ml"
    case .sanskrit, .sanskritRoman: return "sa"
    case .sinhala: return "si"
    case .khmer: return "km"
    case .myanmarBurmese: return "my"
    case .lao: return "lo"
    case .amharic, .amharic1k, .amharic5k: return "am"
    case .armenianWestern, .armenianWestern1k: return "hyw"
    case .greek, .greek1k, .greek5k, .greek10k, .greek25k, .greekKoine,
      .greeklish, .greeklish1k, .greeklish5k, .greeklish10k, .greeklish25k: return "el"
    case .dutch, .dutch1k, .dutch10k: return "nl"
    case .filipino: return "tl"
    case .catalan: return "ca"
    case .indonesian: return "id"
    case .indonesian1k: return "hu"
    case .indonesian10k: return "id"
    case .malay, .malay1k: return "ms"
    case .danish, .danish1k, .danish10k: return "da"
    case .norwegianBokmal, .norwegianBokmal1k, .norwegianBokmal5k,
      .norwegianBokmal10k, .norwegianBokmal150k, .norwegianBokmal600k:
      return "no"
    case .norwegianNynorsk, .norwegianNynorsk1k, .norwegianNynorsk5k,
      .norwegianNynorsk10k, .norwegianNynorsk100k, .norwegianNynorsk400k:
      return "nn"
    case .swedish, .swedish1k, .swedishDiacritics: return "sv"
    case .hungarian, .hungarian1k, .hungarian2k: return "hu"
    case .czech, .czech1k, .czech10k: return "cs"
    case .slovak, .slovak1k, .slovak10k: return "sk"
    case .slovenian, .slovenian1k, .slovenian5k: return "sl"
    case .croatian, .croatian1k: return "hr"
    case .serbian, .serbian10k, .serbianLatin, .serbianLatin10k: return "sr"
    case .bulgarian, .bulgarian1k, .bulgarianLatin, .bulgarianLatin1k: return "bg"
    case .romanian, .romanian1k, .romanian5k, .romanian10k, .romanian25k,
      .romanian50k, .romanian100k, .romanian200k: return "ro"
    case .finnish, .finnish1k, .finnish10k: return "fi"
    case .estonian, .estonian1k, .estonian5k, .estonian10k: return "et"
    case .icelandic: return "is"
    case .french, .french1k, .french2k, .french10k, .french600k: return "fr"
    case .frenchBitoduc: return "fr"
    case .italian, .italian1k, .italian7k, .italian60k, .italian280k: return "it"
    case .esperanto, .esperanto1k, .esperanto10k, .esperanto25k, .esperanto36k,
      .esperantoXSystem, .esperantoXSystem1k, .esperantoXSystem10k,
      .esperantoXSystem25k, .esperantoXSystem36k,
      .esperantoHSystem, .esperantoHSystem1k, .esperantoHSystem10k,
      .esperantoHSystem25k, .esperantoHSystem36k: return "en"
    case .portuguese, .portuguese1k, .portuguese3k, .portuguese5k, .portuguese320k,
      .portuguese550k, .portugueseAccents: return "pt"
    case .simplifiedChinese, .simplifiedChinese1k, .simplifiedChinese5k,
      .simplifiedChinese10k, .simplifiedChinese50k, .traditionalChinese,
      .traditionalChinese1k, .traditionalChinese5k, .traditionalChinese10k,
      .traditionalChinese50k: return "zh"
    case .russian, .russian1k, .russian5k, .russian10k, .russian25k, .russian50k,
      .russian375k, .russianAbbreviations, .russianContractions, .russianContractions1k: return "ru"
    case .ukrainian, .ukrainian1k, .ukrainian10k, .ukrainian50k,
      .ukrainianLatin, .ukrainianLatynka1k, .ukrainianLatynka10k, .ukrainianLatynka50k:
      return "uk"
    case .japaneseHiragana, .japaneseKatakana, .japaneseRomaji: return "ja"
    case .japaneseRomaji1k: return "jp"
    case .korean, .korean1k, .korean5k: return "ko"
    case .turkish, .turkish1k, .turkish5k: return "tr"
    case .polish, .polish2k, .polish5k, .polish10k, .polish20k, .polish40k,
      .polish200k: return "pl"
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
      tokens: tokens, separator: language.usesNoSpaceLiveText ? "" : " ")
  }

  private static func tokens(in rawText: String, language: TypingLanguage) -> [String] {
    guard language.usesNoSpaceLiveText else {
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
  /// Jyutping practice keeps its own tone-number words space-delimited, while
  /// its pinned `zh-Hant` encyclopedia stream is Chinese source text and must
  /// preserve the system tokenizer's no-space boundaries.
  var usesNoSpaceLiveText: Bool {
    usesCJKWordStream || self == .jyutping
  }

  /// Japanese native variants, Ukrainian Latin, Serbian Latin, and Greeklish are intentionally excluded:
  /// those native options promise hiragana-only, katakana-only, ASCII romaji,
  /// ASCII-Latin prompts, Serbian Latin prompts, and ASCII Greeklish prompts respectively,
  /// while a random encyclopedia extract cannot preserve that promise. Chinese
  /// source text remains directly typeable through the selected macOS IME and
  /// is segmented by the system tokenizer above.
  var supportsLiveEncyclopedia: Bool {
    !rawValue.hasPrefix("greeklish") && self != .ukrainianLatin
      && self != .ukrainianLatynka1k && self != .ukrainianLatynka10k
      && self != .ukrainianLatynka50k && self != .serbianLatin && self != .serbianLatin10k
      && self != .japaneseHiragana && self != .japaneseKatakana
      && self != .japaneseRomaji && self != .japaneseRomaji1k
      && (usesSpaceDelimitedWords || self == .simplifiedChinese || self == .traditionalChinese)
  }
}
