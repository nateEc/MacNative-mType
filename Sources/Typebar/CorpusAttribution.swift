import Foundation
import SwiftUI

enum CorpusLicenseNotice: String, CaseIterable, Identifiable {
  case englishLarge = "EnglishLargeCorpusNotices"
  case englishFrequency = "EnglishFrequencyCorpusNotices"
  case spanishFrequency = "SpanishFrequencyCorpusNotices"
  case frenchFrequency = "FrenchFrequencyCorpusNotices"
  case italianFrequency = "ItalianFrequencyCorpusNotices"
  case germanFrequency = "GermanFrequencyCorpusNotices"
  case unicode = "UnicodeNotice"
  case other = "ThirdPartyNotices"

  var id: Self { self }
  var title: String {
    switch self {
    case .englishLarge: "English 450k"
    case .englishFrequency: "基础 English 与频率词库"
    case .spanishFrequency: "Spanish 频率词库"
    case .frenchFrequency: "French 频率词库"
    case .italianFrequency: "Italian 频率词库"
    case .germanFrequency: "Deutsch 词库"
    case .unicode: "Unicode"
    case .other: "其他开源组件"
    }
  }

  func read(resourceDirectory: URL?) -> String? {
    guard let resourceDirectory else { return nil }
    return try? String(contentsOf: resourceDirectory.appendingPathComponent(rawValue + ".txt"),
      encoding: .utf8)
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
      Label("词库与开源署名", systemImage: "text.book.closed")
        .font(.headline)
      Text("English 450k 的独立语料来自 SCOWL、wordfreq 和 UK Advanced Cryptics Dictionary。")
        .fixedSize(horizontal: false, vertical: true)
      Text(LargeEnglishAttribution.sourceName)
        .font(.body.weight(.semibold))
      Text(LargeEnglishAttribution.copyright)
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Text("German 大档语料来自 German Wiktionary contributors，经 Kaikki.org / Wiktextract 提取。")
        .fixedSize(horizontal: false, vertical: true)
      Button("查看完整许可…") { showingNotices = true }
        .buttonStyle(.link)
    }
    .sheet(isPresented: $showingNotices) { CorpusLicensesView() }
  }
}

struct CorpusLicensesView: View {
  let resourceDirectory: URL?
  @Environment(\.dismiss) private var dismiss
  @State private var selectedNotice = CorpusLicenseNotice.englishLarge
  @State private var text: String?
  @State private var hasLoaded = false

  init(resourceDirectory: URL? = Bundle.main.resourceURL) {
    self.resourceDirectory = resourceDirectory
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
