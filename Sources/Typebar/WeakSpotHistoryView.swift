import SwiftData
import SwiftUI

struct WeakSpotHistoryView: View {
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var records:
    [TestResultRecord]

  let englishVariant: EnglishVariant
  let onStart: (String, TypingLanguage) -> Void
  @State private var selectedLanguage: TypingLanguage
  @State private var wordCount = 25

  init(
    initialLanguage: TypingLanguage,
    englishVariant: EnglishVariant,
    onStart: @escaping (String, TypingLanguage) -> Void
  ) {
    self.englishVariant = englishVariant
    self.onStart = onStart
    _selectedLanguage = State(initialValue: initialLanguage)
  }

  private var results: [CompletedTestResult] { records.compactMap(\.portableResult) }

  private var availableLanguages: [TypingLanguage] {
    let recordedLanguages = Set(results.map(\.configuration.language))
    return TypingLanguage.allCases.filter {
      recordedLanguages.contains($0)
        && WeakSpotPractice.report(
          results: results, language: $0, englishVariant: englishVariant) != nil
    }
  }

  private var report: WeakSpotReport? {
    WeakSpotPractice.report(
      results: results, language: selectedLanguage, englishVariant: englishVariant)
  }

  var body: some View {
    NavigationStack {
      Group {
        if availableLanguages.isEmpty {
          ContentUnavailableView(
            "暂无弱项数据", systemImage: "scope",
            description: Text("完成并保存一轮带按键时间回放的单词练习后，这里会在本机分析偏慢或易错字符。"))
        } else {
          Form {
            Section("分析范围") {
              Picker("语言", selection: $selectedLanguage) {
                ForEach(availableLanguages, id: \.self) { language in
                  Text(language.displayName).tag(language)
                }
              }
              if let report {
                LabeledContent("本机回放", value: "\(report.analyzedResultCount) 轮")
                LabeledContent("记录的错误", value: "\(report.totalMistakeCount) 次")
                LabeledContent("分析字符", value: "\(report.characters.count) 个")
              }
            }

            if let report {
              Section("弱项字符") {
                ForEach(report.characters.prefix(12)) { item in
                  HStack {
                    Text(String(item.character))
                      .font(.system(size: 24, weight: .semibold, design: .rounded))
                      .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                      Text("错误 \(item.mistakeCount) 次 · 尝试 \(item.attemptCount) 次")
                      if let milliseconds = item.averageIntervalMilliseconds {
                        Text("平均输入间隔 \(milliseconds) ms")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                    Spacer()
                  }
                  .accessibilityElement(children: .combine)
                }
              }

              Section("Typebar 自有候选词") {
                Text(report.suggestedWords.joined(separator: " · "))
                  .textSelection(.enabled)
                Text("候选按易错和偏慢字符共同排序，只来自所选语言的 Typebar 自写离线词流；分析不会离开这台 Mac。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Section("开始训练") {
                Picker("词数", selection: $wordCount) {
                  ForEach([10, 25, 50], id: \.self) { count in
                    Text("\(count)").tag(count)
                  }
                }
                .pickerStyle(.segmented)
                Button("开始 \(wordCount) 词弱项训练", systemImage: "play.fill") {
                  guard let prompt = WeakSpotPractice.prompt(
                    results: results, language: selectedLanguage,
                    englishVariant: englishVariant, wordCount: wordCount)
                  else { return }
                  dismiss()
                  onStart(prompt, selectedLanguage)
                }
                .buttonStyle(.borderedProminent)
              }
            }
          }
        }
      }
      .navigationTitle("弱项分析")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
        }
      }
    }
    .frame(minWidth: 500, minHeight: 430)
    .onAppear { selectAvailableLanguageIfNeeded() }
    .onChange(of: availableLanguages) { _, _ in selectAvailableLanguageIfNeeded() }
  }

  private func selectAvailableLanguageIfNeeded() {
    guard !availableLanguages.contains(selectedLanguage), let first = availableLanguages.first else {
      return
    }
    selectedLanguage = first
  }
}
