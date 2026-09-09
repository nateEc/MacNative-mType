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
      targetCount = configuration.isInfinite ? 100 : configuration.wordLimit ?? 25
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
    case .english, .english1k, .english5k, .english10k, .english25k, .english450k,
      .englishFiveLetter, .englishCommonlyMisspelled, .englishContractions,
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
    case .hausa: return "ha"
    case .tatar, .tatar1k, .tatar5k, .tatar9k: return "tt"
    case .tatarCrimean, .tatarCrimean1k, .tatarCrimean5k, .tatarCrimean10k,
      .tatarCrimean15k, .tatarCrimeanCyrillic, .tatarCrimeanCyrillic1k,
      .tatarCrimeanCyrillic5k, .tatarCrimeanCyrillic10k,
      .tatarCrimeanCyrillic15k: return "crh"
    case .klingon: return "tlh"
    case .quenya: return "en"
    case .viossa, .viossaNjutro: return "en"
    case .maori: return "en"
    case .lojbanGismu, .lojbanCmavo: return "en"
    case .uzbek, .uzbek1k, .uzbek70k: return "uz"
    case .occitan, .occitan1k, .occitan2k, .occitan5k, .occitan10k: return "oc"
    case .oromo: return "om"
    case .jyutping: return "zh"
    case .bashkir: return "ba"
    case .basque: return "eu"
    case .frisian: return "fy"
    case .hawaiian: return "haw"
    case .kabyle, .kabyle1k, .kabyle2k, .kabyle5k, .kabyle10k: return "kab"
    case .maltese: return "mt"
    case .xhosa: return "xh"
    case .tibetan: return "bo"
    case .kyrgyz, .kyrgyz1k: return "ky"
    case .kinyarwanda: return "rw"
    case .shona: return "en"
    case .santali: return "sat"
    case .yiddish: return "yi"
    case .friulian: return "fur"
    case .bemba: return "bem"
    case .azerbaijani, .azerbaijani1k: return "az"
    case .belarusian, .belarusian1k, .belarusian5k, .belarusian10k, .belarusian25k,
      .belarusian50k, .belarusian100k: return "be"
    case .belarusianLacinka: return "en"
    case .latvian: return "lv"
    case .irish: return "ga"
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
    case .amharic: return "am"
    case .armenianWestern: return "hyw"
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
    case .hungarian: return "hu"
    case .czech, .czech1k, .czech10k: return "cs"
    case .slovak, .slovak1k, .slovak10k: return "sk"
    case .slovenian, .slovenian1k, .slovenian5k: return "sl"
    case .croatian, .croatian1k: return "hr"
    case .serbian, .serbianLatin: return "sr"
    case .bulgarian, .bulgarianLatin: return "bg"
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
    isNoSpaceLanguage || self == .jyutping
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
      && self != .ukrainianLatynka50k && self != .serbianLatin && self != .japaneseRomaji
      && (usesSpaceDelimitedWords || self == .simplifiedChinese || self == .traditionalChinese)
  }
}
