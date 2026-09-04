import Foundation
import SwiftUI

/// Generates local custom practice text from user-supplied fragments.
/// No bundled third-party word lists or remote content are used.
struct CustomTextGenerator {
  struct Settings: Equatable {
    var fragments = ""
    var minimumFragments = 2
    var maximumFragments = 5
    var wordCount = 100
  }

  enum Error: LocalizedError, Equatable {
    case emptyFragments
    case invalidFragmentRange
    case invalidWordCount
    case exceedsCustomTextLimit

    var errorDescription: String? {
      switch self {
      case .emptyFragments: "请至少输入一个用空白分隔的片段。"
      case .invalidFragmentRange: "每词最少片段不能大于最多片段，且两者范围为 1–20。"
      case .invalidWordCount: "词数范围为 1–1,000。"
      case .exceedsCustomTextLimit: "按当前设置生成的文本可能超过 10,000 字符。"
      }
    }
  }

  static func generate<R: RandomNumberGenerator>(
    settings: Settings, using generator: inout R
  ) -> Result<String, Error> {
    let fragments = settings.fragments.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !fragments.isEmpty else { return .failure(.emptyFragments) }
    guard (1...20).contains(settings.minimumFragments),
      (settings.minimumFragments...20).contains(settings.maximumFragments)
    else {
      return .failure(.invalidFragmentRange)
    }
    guard (1...1_000).contains(settings.wordCount) else { return .failure(.invalidWordCount) }

    let longestFragment = fragments.map(\.count).max() ?? 0
    let separatorCount = settings.wordCount - 1
    let maximumFragmentLength =
      (CustomTextPolicy.maximumLength - separatorCount) / settings.wordCount
        / settings.maximumFragments
    guard longestFragment <= maximumFragmentLength else {
      return .failure(.exceedsCustomTextLimit)
    }

    var words: [String] = []
    words.reserveCapacity(settings.wordCount)
    for _ in 0..<settings.wordCount {
      let fragmentCount = Int.random(
        in: settings.minimumFragments...settings.maximumFragments, using: &generator)
      var word = ""
      for _ in 0..<fragmentCount {
        let index = Int.random(in: fragments.indices, using: &generator)
        word += fragments[index]
      }
      words.append(word)
    }
    return .success(words.joined(separator: " "))
  }
}

struct CustomTextGeneratorView: View {
  private let onApply: (String, Bool) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var fragments = "a s d f g h j k l"
  @State private var minimumFragments = 2
  @State private var maximumFragments = 5
  @State private var wordCount = 100
  @State private var errorMessage: String?

  init(onApply: @escaping (String, Bool) -> Void) {
    self.onApply = onApply
  }

  private var settings: CustomTextGenerator.Settings {
    .init(
      fragments: fragments, minimumFragments: minimumFragments,
      maximumFragments: maximumFragments, wordCount: wordCount)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("片段") {
          TextEditor(text: $fragments)
            .font(.body.monospaced())
            .frame(minHeight: 110)
          Text("用空白分隔字符或短片段；每个生成词会随机连接其中的若干项。")
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack {
            Button("主排字母") { fragments = "a s d f g h j k l" }
            Button("数字") { fragments = "0 1 2 3 4 5 6 7 8 9" }
            Button("符号") { fragments = "! ? # % + = - _" }
          }
        }

        Section("组合") {
          Stepper(value: $minimumFragments, in: 1...20) {
            LabeledContent("每词最少片段", value: "\(minimumFragments)")
          }
          Stepper(value: $maximumFragments, in: 1...20) {
            LabeledContent("每词最多片段", value: "\(maximumFragments)")
          }
          Stepper(value: $wordCount, in: 1...1_000) {
            LabeledContent("生成词数", value: "\(wordCount)")
          }
          Text("生成前会检查 Typebar 自定义文本的 10,000 字符上限。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
          }
        }

        Section {
          Button("替换自定义文本并开始") { generate(appending: false) }
          Button("追加到自定义文本并开始") { generate(appending: true) }
        }
      }
      .navigationTitle("生成练习文本")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
    .frame(minWidth: 560, minHeight: 490)
  }

  private func generate(appending: Bool) {
    var generator = SystemRandomNumberGenerator()
    switch CustomTextGenerator.generate(settings: settings, using: &generator) {
    case .success(let text):
      onApply(text, appending)
      dismiss()
    case .failure(let error):
      errorMessage = error.errorDescription
    }
  }
}
