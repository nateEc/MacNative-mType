import AVFoundation

/// Local accessibility reading backed only by voices bundled with macOS.
@MainActor
final class NativeSpeech {
  static let shared = NativeSpeech()
  private let synthesizer = AVSpeechSynthesizer()

  func speak(_ text: String, language: TypingLanguage) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: normalized)
    utterance.voice = AVSpeechSynthesisVoice(language: language.speechLocaleIdentifier)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
  }

  func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

extension TypingLanguage {
  var speechLocaleIdentifier: String {
    if isCodeLanguage { return "en-US" }
    return switch self {
    case .english, .english1k, .english5k, .english10k, .english25k, .english450k,
      .englishFiveLetter, .englishCommonlyMisspelled, .englishContractions,
      .englishDoubleLetter, .englishLegal, .englishMedical, .englishShakespearean,
      .oldEnglish, .ukrainianEndings, .ukrainianLatynkaEndings: "en-US"
    case .kokanu: "xxs-Lat"
    case .likanu: "xxs-Uixs"
    case .pokemon1k, .arenaStrategy: "en"
    case .pigLatin, .loremIpsum, .git: "en-US"
    case .spanish, .spanish1k, .spanish10k, .spanish650k: "es-ES"
    case .german, .german1k, .german10k, .german250k: "de-DE"
    case .swissGerman, .swissGerman1k, .swissGerman2k: "de-CH"
    case .afrikaans, .afrikaans1k, .afrikaans10k: "af-ZA"
    case .hausa, .hausa1k: "ha"
    case .tatar, .tatar1k, .tatar5k, .tatar9k: "tt"
    case .tatarCrimean, .tatarCrimean1k, .tatarCrimean5k, .tatarCrimean10k,
      .tatarCrimean15k, .tatarCrimeanCyrillic, .tatarCrimeanCyrillic1k,
      .tatarCrimeanCyrillic5k, .tatarCrimeanCyrillic10k,
      .tatarCrimeanCyrillic15k: "crh-CRH"
    case .klingon: "tlh"
    case .quenya: "en-US"
    case .viossa, .viossaNjutro: "en-US"
    case .maori: "en-US"
    case .lojbanGismu, .lojbanCmavo: "en-US"
    case .uzbek, .uzbek1k, .uzbek70k: "uz-UZ"
    case .occitan, .occitan1k, .occitan2k, .occitan5k, .occitan10k: "oc-FR"
    case .oromo: "om"
    case .jyutping: "zh-Hant"
    case .bashkir: "ba"
    case .basque: "eu"
    case .frisian, .frisian1k: "fy-FY"
    case .hawaiian: "haw"
    case .kabyle, .kabyle1k, .kabyle2k, .kabyle5k, .kabyle10k: "kab"
    case .maltese, .maltese1k: "mt"
    case .xhosa: "xh"
    case .tibetan: "bo-TI"
    case .kyrgyz, .kyrgyz1k: "ky-KY"
    case .kinyarwanda: "rw-RW"
    case .shona: "en-US"
    case .santali: "sat-IN"
    case .yiddish: "yi"
    case .friulian: "fur"
    case .bemba, .bemba1k, .bemba10k: "bem"
    case .azerbaijani, .azerbaijani1k: "az-AZ"
    case .belarusian, .belarusian1k, .belarusian5k, .belarusian10k, .belarusian25k,
      .belarusian50k, .belarusian100k: "be-BY"
    case .belarusianLacinka: "en-US"
    case .latvian, .latvian1k: "lv"
    case .irish, .irish1k: "ga-IE"
    case .galician: "gl-ES"
    case .kurdishCentral, .kurdishCentral2k, .kurdishCentral4k: "ckb"
    case .arabic, .arabic10k: "ar-SA"
    case .arabicEgypt, .arabicEgypt1k: "ar-EG"
    case .arabicMorocco: "ar-MA"
    case .pashto: "ps"
    case .sindhi: "sd"
    case .hebrew, .hebrew1k, .hebrew5k, .hebrew10k: "he-IL"
    case .persian, .persian1k, .persian5k, .persian20k: "fa-IR"
    case .persianRomanized: "fa"
    case .urdu, .urdu1k, .urdu5k: "ur-PK"
    case .urduRoman: "ur-Latn"
    case .urdish: "en-US"
    case .tamil, .tamil1k, .tamilOld: "ta-IN"
    case .tanglish: "en-US"
    case .hindi, .hindi1k: "hi-IN"
    case .hinglish: "en-US"
    case .gujarati, .gujarati1k: "gu-IN"
    case .bangla, .bangla10k, .banglaLetters: "bn-BD"
    case .thai, .thai1k, .thai5k, .thai10k, .thai20k, .thai50k, .thai60k: "th-TH"
    case .nepali, .nepali1k: "ne-NP"
    case .nepaliRomanized: "en-US"
    case .kannada: "kn-IN"
    case .telugu, .telugu1k: "te-IN"
    case .malayalam: "ml-IN"
    case .sanskrit, .sanskritRoman: "sa"
    case .sinhala: "si"
    case .khmer: "km-KH"
    case .myanmarBurmese: "my-MM"
    case .lao: "lo"
    case .amharic: "am-ET"
    case .armenianWestern: "hyw"
    case .greek, .greek1k, .greek5k, .greek10k, .greek25k, .greekKoine,
      .greeklish, .greeklish1k, .greeklish5k, .greeklish10k, .greeklish25k: "el-GR"
    case .dutch, .dutch1k, .dutch10k: "nl-NL"
    case .filipino: "fil-PH"
    case .catalan: "ca-ES"
    case .indonesian: "id-ID"
    case .indonesian1k: "hu-HU"
    case .indonesian10k: "id-ID"
    case .malay, .malay1k: "ms-MY"
    case .danish, .danish1k, .danish10k: "da-DK"
    case .norwegianBokmal, .norwegianBokmal1k, .norwegianBokmal5k,
      .norwegianBokmal10k, .norwegianBokmal150k, .norwegianBokmal600k:
      "nb-NO"
    case .norwegianNynorsk, .norwegianNynorsk1k, .norwegianNynorsk5k,
      .norwegianNynorsk10k, .norwegianNynorsk100k, .norwegianNynorsk400k:
      "nn-NO"
    case .swedish, .swedish1k, .swedishDiacritics: "sv-SE"
    case .hungarian, .hungarian1k, .hungarian2k: "hu-HU"
    case .czech, .czech1k, .czech10k: "cs-CZ"
    case .slovak, .slovak1k, .slovak10k: "sk-SK"
    case .slovenian, .slovenian1k, .slovenian5k: "sl-SI"
    case .croatian, .croatian1k: "hr-HR"
    case .serbian: "sr-RS"
    case .serbian10k: "sr-Cyrl"
    case .serbianLatin: "sr-RS"
    case .serbianLatin10k: "sr-Latn"
    case .bulgarian: "bg-BG"
    case .bulgarian1k, .bulgarianLatin, .bulgarianLatin1k: "bg"
    case .romanian, .romanian1k, .romanian5k, .romanian10k, .romanian25k,
      .romanian50k, .romanian100k, .romanian200k: "ro-RO"
    case .finnish, .finnish1k, .finnish10k: "fi-FI"
    case .estonian, .estonian1k, .estonian5k, .estonian10k: "et-EE"
    case .icelandic: "is-IS"
    case .french, .french1k, .french2k, .french10k, .french600k: "fr-FR"
    case .frenchBitoduc: "fr-fr"
    case .italian, .italian1k, .italian7k, .italian60k, .italian280k: "it-IT"
    case .esperanto, .esperanto1k, .esperanto10k, .esperanto25k, .esperanto36k,
      .esperantoXSystem, .esperantoXSystem1k, .esperantoXSystem10k,
      .esperantoXSystem25k, .esperantoXSystem36k,
      .esperantoHSystem, .esperantoHSystem1k, .esperantoHSystem10k,
      .esperantoHSystem25k, .esperantoHSystem36k: "en-US"
    case .portuguese, .portuguese3k, .portugueseAccents: "pt-PT"
    case .portuguese1k: "pt-BR"
    case .portuguese5k, .portuguese320k, .portuguese550k: "pt"
    case .simplifiedChinese, .simplifiedChinese1k, .simplifiedChinese5k,
      .simplifiedChinese10k, .simplifiedChinese50k, .mixedEnglishChinese: "zh-CN"
    case .traditionalChinese, .traditionalChinese1k, .traditionalChinese5k,
      .traditionalChinese10k, .traditionalChinese50k: "zh-TW"
    case .russian, .russian1k, .russian5k, .russian10k, .russian25k, .russian50k,
      .russian375k, .russianAbbreviations, .russianContractions, .russianContractions1k: "ru-RU"
    case .ukrainian, .ukrainian1k, .ukrainian10k, .ukrainian50k,
      .ukrainianLatin, .ukrainianLatynka1k, .ukrainianLatynka10k, .ukrainianLatynka50k: "uk-UA"
    case .japaneseHiragana, .japaneseKatakana, .japaneseRomaji: "ja-JP"
    case .korean, .korean1k, .korean5k: "ko-KR"
    case .turkish, .turkish1k, .turkish5k: "tr-TR"
    case .polish, .polish2k, .polish5k, .polish10k, .polish20k, .polish40k,
      .polish200k: "pl-PL"
    case .mixedLanguages: "en-US"
    default: "en-US"
    }
  }
}
