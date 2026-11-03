import Foundation
import SwiftUI

enum CorpusLicenseNotice: String, CaseIterable, Identifiable {
  case englishLarge = "EnglishLargeCorpusNotices"
  case englishFiveLetter = "EnglishFiveLetterCorpusNotices"
  case ukrainian = "UkrainianCorpusNotices"
  case ukrainianLatynka = "UkrainianLatynkaCorpusNotices"
  case greek = "GreekCorpusNotices"
  case indonesian = "IndonesianCorpusNotices"
  case malay = "MalayCorpusNotices"
  case vietnamese = "VietnameseCorpusNotices"
  case turkish = "TurkishCorpusNotices"
  case kazakh = "KazakhCorpusNotices"
  case kyrgyz = "KyrgyzCorpusNotices"
  case azerbaijani = "AzerbaijaniCorpusNotices"
  case mongolian = "MongolianCorpusNotices"
  case korean = "KoreanCorpusNotices"
  case nepali = "NepaliCorpusNotices"
  case hindi = "HindiCorpusNotices"
  case gujarati = "GujaratiCorpusNotices"
  case tamil = "TamilCorpusNotices"
  case telugu = "TeluguCorpusNotices"
  case simplifiedChinese = "SimplifiedChineseCorpusNotices"
  case traditionalChinese = "TraditionalChineseCorpusNotices"
  case englishFrequency = "EnglishFrequencyCorpusNotices"
  case spanishFrequency = "SpanishFrequencyCorpusNotices"
  case spanishLarge = "SpanishLargeCorpusNotices"
  case frenchFrequency = "FrenchFrequencyCorpusNotices"
  case frenchLarge = "FrenchLargeCorpusNotices"
  case italianFrequency = "ItalianFrequencyCorpusNotices"
  case germanFrequency = "GermanFrequencyCorpusNotices"
  case romanian = "RomanianCorpusNotices"
  case polish = "PolishCorpusNotices"
  case portuguese = "PortugueseCorpusNotices"
  case esperanto = "EsperantoCorpusNotices"
  case norwegian = "NorwegianCorpusNotices"
  case norwegianBasic = "NorwegianBasicCorpusNotices"
  case russian = "RussianCorpusNotices"
  case russianBasic = "RussianBasicCorpusNotices"
  case unicode = "UnicodeNotice"
  case other = "ThirdPartyNotices"

  var id: Self { self }
  var title: String {
    switch self {
    case .englishLarge: "English 450k"
    case .englishFiveLetter: "English · Five Letter"
    case .ukrainian: "Українська"
    case .ukrainianLatynka: "Українська (Latynka)"
    case .greek: "Ελληνικά"
    case .indonesian: "Bahasa Indonesia · 三档词库"
    case .malay: "Bahasa Melayu · 两档词库"
    case .vietnamese: "Tiếng Việt · 三档词库"
    case .turkish: "Türkçe · 三档词库"
    case .kazakh: "Қазақша · 两档词库"
    case .kyrgyz: "Кыргызча · 两档词库"
    case .azerbaijani: "Azərbaycanca · 两档词库"
    case .mongolian: "Монгол · 两档词库"
    case .korean: "한국어 · 三档词库"
    case .nepali: "नेपाली · 两档词库"
    case .hindi: "हिन्दी · 两档词库"
    case .gujarati: "ગુજરાતી · 两档词库"
    case .tamil: "தமிழ் · 三档内容"
    case .telugu: "తెలుగు · 两档内容"
    case .simplifiedChinese: "简体中文 · 五档词库"
    case .traditionalChinese: "繁體中文 · 五檔詞庫"
    case .englishFrequency: "基础 English 与频率词库"
    case .spanishFrequency: "Spanish 频率词库"
    case .spanishLarge: "Español · 650k"
    case .frenchFrequency: "French 频率词库"
    case .frenchLarge: "Français · 600k"
    case .italianFrequency: "Italian 频率词库"
    case .germanFrequency: "Deutsch 词库"
    case .romanian: "Română · 规模词库"
    case .polish: "Polski · 规模词库"
    case .portuguese: "Português · 规模词库"
    case .esperanto: "Esperanto · 规模词库"
    case .norwegian: "Norsk · Bokmål／Nynorsk"
    case .norwegianBasic: "Norsk · 基础词库"
    case .russian: "Русский · 规模词库"
    case .russianBasic: "Русский · 基础词库"
    case .unicode: "Unicode"
    case .other: "其他开源组件"
    }
  }

  func read(resourceDirectory: URL?) -> String? {
    guard let resourceDirectory else { return nil }
    guard let text = try? String(contentsOf: resourceDirectory.appendingPathComponent(rawValue + ".txt"),
      encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }
}

enum LargeEnglishAttribution {
  static let sourceName = "UK Advanced Cryptics Dictionary"
  static let copyright = "Copyright (c) J Ross Beresford 1993-1999. All Rights Reserved."
}

/// Uses notice metadata only; opening About does not initialize the large word array.
struct CorpusAttributionSummary: View {
  @State private var showingNotices = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Label("词库与开源署名", systemImage: "text.book.closed")
          .font(.headline)
        Spacer(minLength: 12)
        Button("查看完整许可…") { showingNotices = true }
          .buttonStyle(.link)
      }
      Text("English 五字母／450k 的独立语料来自 SCOWL、wordfreq 和 UK Advanced Cryptics Dictionary。")
        .fixedSize(horizontal: false, vertical: true)
      Text(LargeEnglishAttribution.sourceName)
        .font(.body.weight(.semibold))
      Text(LargeEnglishAttribution.copyright)
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Text("German 大档语料来自 German Wiktionary contributors，经 Kaikki.org / Wiktextract 提取。")
        .fixedSize(horizontal: false, vertical: true)
      Text("French 600k 来自 Wiktionnaire contributors、Kaikki.org / Wiktextract 和 wordfreq。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Spanish 650k 来自 Wikcionario / Wiktionnaire contributors、Kaikki.org / Wiktextract 和 wordfreq，包含 13 个明确标注的书写练习改编。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Română 规模词库来自 English Wiktionary contributors、Kaikki.org / Wiktextract 和 wordfreq。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Polski 规模词库来自 Wikisłownik contributors、Kaikki.org / Wiktextract 和 wordfreq。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Português 规模词库来自 Wikcionário contributors、Kaikki.org / Wiktextract 和 wordfreq，另含两个明确标注的单位书写示例。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Esperanto 规模词库来自 English Wiktionary contributors、Kaikki.org / Wiktextract，按 Tatoeba contributors 的句子词频选编，包含独立的 X／H 拼写转换。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Norsk bokmål／nynorsk 规模词库来自 Norsk ordbank，由 Nasjonalbiblioteket / Språkbanken 发布；两种书面语分别按其官方 unigram 数据选编。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Русский 规模词库来自 Russian Wiktionary contributors、Kaikki.org / Wiktextract，按独立 wordfreq 观察频率编排，保留实际词形与大小写。")
        .fixedSize(horizontal: false, vertical: true)
      Text("Українська 词库来自 English／Russian Wiktionary、Kaikki.org 和 Wikipedia contributors；保留注音改编与逐词出处。")
      Text("Українська (Latynka) 为上述独立西里尔语料的明确拉丁化改编，参照 Vakulenko 的现代字母规则并保留原词；频率证据仅指西里尔原形。")
      Text("Ελληνικά 词库来自 English Wiktionary contributors、Kaikki.org 与 wordfreq；保留原样声调、分音符及词尾 sigma，不改写拼写。")
      Text("Bahasa Indonesia 三档词库来自 English Wiktionary contributors、Kaikki.org 与 wordfreq；保留原样大小写、连字符和旧自有词，并提供逐词来源。")
      Text("Bahasa Melayu 两档词库来自 English Wiktionary contributors／Kaikki.org，并按 Tatoeba 的标准马来语语料选编；保留旧自有词和逐词出处。")
      Text("Tiếng Việt 三档词库来自 English Wiktionary contributors／Kaikki.org 与 wordfreq；保留 30 个旧自有词、完整重音键集和逐词出处，基础额外保留 nhẫn 的 ẫ。")
      Text("Türkçe 三档词库来自 English Wiktionary contributors／Kaikki.org 与 wordfreq；短语按 Tatoeba 整短语观察选编，保留旧自有词和逐词出处。")
      Text("Қазақша 两档词库来自 English Wiktionary contributors／Kaikki.org，按 Tatoeba 完整词项观察选编；保留旧词、连字符和短语，并提供逐词出处。")
      Text("Кыргызча 两档词库来自 English Wiktionary contributors／Kaikki.org；三个逗号词项直接节选自 Tatoeba，保留原样大小写、旧词与逐项出处。")
      Text("Azərbaycanca 两档词库来自 English Wiktionary contributors／Kaikki.org；两个组合点词项明确记录 Unicode 大小写改编与原始拼写，并保留旧词。")
      Text("Монгол 两档词库使用独立词典和 Tatoeba 原样大写词项；一个 Ё 首字母改编单独标明，逐项提供原词、句子出处及署名。")
      Text("한국어 三档词库使用独立词典和 wordfreq 原样词元；各档音节集合分开保留，旧词额外音节和逐项来源明确列出。")
      Text("नेपाली 两档词库使用独立词典与 Tatoeba 整词观察，保留旧词和组合标记；UTF-16 与字素边界分别验证，旧词出处缺失明确标记。")
      Text("हिन्दी 两档内容来自独立词典，按 wordfreq 与 Tatoeba 整词观察排序；字符练习与词汇分开标注，保留旧词和组合标记。")
      Text("ગુજરાતી 两档内容使用独立词典与有出处的 Tatoeba 原样摘录，保留多词项及边缘空格；字符练习和八个旧自有词单独标明。")
      Text("தமிழ் 三档内容使用独立词典、wordfreq 与 Tatoeba 整词观察；旧版三个自有练习保留，字符项与旧词来源单独标注。")
      Text("తెలుగు 两档内容保留组合标记、原样多词项和旧词；词典字符与 Tatoeba 摘录分别提供来源和许可。")
      Text("简体中文五档词库来自 MDBG／CC-CEDICT 与 wordfreq；保留旧自有词，并逐词标明三项书写改编及原始出处。")
        .fixedSize(horizontal: false, vertical: true)
      Text("繁體中文五檔詞庫直接採用 CC-CEDICT 的繁體原形；保留舊自有詞，逐詞標明來源與書寫改編。簡體對應詞的頻率觀察不代表繁體詞頻。")
        .fixedSize(horizontal: false, vertical: true)
    }
    .sheet(isPresented: $showingNotices) { CorpusLicensesView() }
  }
}

struct CorpusLicensesView: View {
  let resourceDirectory: URL?
  @State private var selectedNotice = CorpusLicenseNotice.englishLarge

  init(resourceDirectory: URL? = Bundle.main.resourceURL) {
    self.resourceDirectory = resourceDirectory
  }

  var body: some View {
    CorpusLicenseReader(resourceDirectory: resourceDirectory, selectedNotice: $selectedNotice)
  }
}

struct CorpusLicenseReader: View {
  let resourceDirectory: URL?
  @Binding var selectedNotice: CorpusLicenseNotice
  @Environment(\.dismiss) private var dismiss
  @State private var text: String?
  @State private var hasLoaded = false

  init(resourceDirectory: URL?, selectedNotice: Binding<CorpusLicenseNotice>) {
    self.resourceDirectory = resourceDirectory
    self._selectedNotice = selectedNotice
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("词库与开源许可").font(.title2.weight(.semibold))
      Picker("许可", selection: $selectedNotice) {
        ForEach(CorpusLicenseNotice.allCases) { notice in
          Text(notice.title).tag(notice)
        }
      }
      ScrollView {
        if let text {
          Text(verbatim: text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if hasLoaded {
          Label("此安装包的许可文件无法读取，请重新安装。", systemImage: "exclamationmark.triangle")
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ProgressView("正在读取许可…")
        }
      }
      .id(selectedNotice)
      HStack {
        Spacer()
        Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }
    .padding(24)
    .frame(width: 560, height: 620)
    .task(id: selectedNotice) {
      hasLoaded = false
      text = selectedNotice.read(resourceDirectory: resourceDirectory)
      hasLoaded = true
    }
  }
}
