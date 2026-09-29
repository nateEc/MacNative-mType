import Foundation
import SwiftUI

/// Local-only filtering for Typebar-authored lexicons. It intentionally does
/// not download or derive words from the Monkeytype reference repository.
struct LocalWordFilter {
  struct Criteria: Equatable {
    var includeCharacters = ""
    var excludeCharacters = ""
    var minimumLength: Int?
    var maximumLength: Int?
    var regularExpression = ""
    var exactCharactersOnly = false
  }

  enum Error: LocalizedError, Equatable {
    case exactCharactersNeedInclude
    case invalidLengthRange
    case invalidRegularExpression

    var errorDescription: String? {
      switch self {
      case .exactCharactersNeedInclude: "“仅使用允许字符”需要至少输入一个允许字符。"
      case .invalidLengthRange: "最短词长不能大于最长词长。"
      case .invalidRegularExpression: "正则表达式无效。"
      }
    }
  }

  static func words<Lexicon: Collection>(
    in lexicon: Lexicon, matching criteria: Criteria
  ) -> Result<[String], Error> where Lexicon.Element == String {
    let included = characterSet(from: criteria.includeCharacters)
    let excluded = characterSet(from: criteria.excludeCharacters)
    if criteria.exactCharactersOnly && included.isEmpty {
      return .failure(.exactCharactersNeedInclude)
    }
    if let minimum = criteria.minimumLength, let maximum = criteria.maximumLength, minimum > maximum {
      return .failure(.invalidLengthRange)
    }

    let expression: NSRegularExpression?
    let pattern = criteria.regularExpression.trimmingCharacters(in: .whitespacesAndNewlines)
    if criteria.exactCharactersOnly || pattern.isEmpty {
      expression = nil
    } else {
      do {
        expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
      } catch {
        return .failure(.invalidRegularExpression)
      }
    }

    return .success(lexicon.filter { word in
      let length = word.count
      if let minimum = criteria.minimumLength, length < minimum { return false }
      if let maximum = criteria.maximumLength, length > maximum { return false }
      let characters = Array(word.lowercased())
      if criteria.exactCharactersOnly {
        guard characters.allSatisfy(included.contains) else { return false }
      } else {
        if !included.isEmpty && !characters.contains(where: included.contains) { return false }
        if !excluded.isEmpty && characters.contains(where: excluded.contains) { return false }
      }
      guard let expression else { return true }
      let range = NSRange(word.startIndex..., in: word)
      return expression.firstMatch(in: word, range: range) != nil
    })
  }

  private static func characterSet(from value: String) -> Set<Character> {
    Set(value.lowercased().filter { !$0.isWhitespace })
  }
}

/// Layout-based word-filter presets. The source uses only each key's primary
/// output, never shifted/Option glyphs or the number row.
enum LocalWordFilterPreset: String, CaseIterable, Identifiable {
  case homeKeys
  case leftHand
  case rightHand
  case homeRow
  case topRow
  case bottomRow

  var id: Self { self }

  var title: String {
    switch self {
    case .homeKeys: "主键位"
    case .leftHand: "左手"
    case .rightHand: "右手"
    case .homeRow: "中排"
    case .topRow: "上排"
    case .bottomRow: "下排"
    }
  }

  func criteria(layout: KeyboardLayout) -> LocalWordFilter.Criteria? {
    let rows = KeyboardGuideModel.rows(for: layout)
    guard rows.count >= 4 else { return nil }
    let top = rows[1]
    let home = rows[2]
    let bottom = rows[3]
    let selected: [KeyboardGuideKey]
    switch self {
    case .homeKeys:
      selected = Array(home.prefix(4)) + Array(home.dropFirst(6).prefix(4))
    case .leftHand:
      selected = Array(top.prefix(5)) + Array(home.prefix(5)) + Array(bottom.prefix(5))
    case .rightHand:
      selected = Array(top.dropFirst(5)) + Array(home.dropFirst(5))
        + Array(bottom.dropFirst(4))
    case .homeRow: selected = home
    case .topRow: selected = top
    case .bottomRow: selected = bottom
    }
    let labels = selected.compactMap { key -> String? in
      key.label.count == 1 ? key.label : nil
    }
    guard !labels.isEmpty else { return nil }
    return .init(includeCharacters: labels.joined(separator: " "), exactCharactersOnly: true)
  }
}

struct WordFilterView: View {
  private let onApply: (String, Bool) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var language: TypingLanguage
  @State private var layout: KeyboardLayout
  @State private var preset: LocalWordFilterPreset = .leftHand
  @State private var includeCharacters = ""
  @State private var excludeCharacters = ""
  @State private var minimumLength = ""
  @State private var maximumLength = ""
  @State private var regularExpression = ""
  @State private var exactCharactersOnly = false

  init(
    language: TypingLanguage, layout: KeyboardLayout,
    onApply: @escaping (String, Bool) -> Void
  ) {
    _language = State(initialValue: language.supportsLocalWordFilter ? language : .english)
    _layout = State(initialValue: layout)
    self.onApply = onApply
  }

  private var selectableLanguages: [TypingLanguage] {
    TypingLanguage.allCases.filter(\.supportsLocalWordFilter)
  }

  private var criteria: LocalWordFilter.Criteria {
    .init(
      includeCharacters: includeCharacters, excludeCharacters: excludeCharacters,
      minimumLength: Int(minimumLength), maximumLength: Int(maximumLength),
      regularExpression: regularExpression, exactCharactersOnly: exactCharactersOnly)
  }

  private var filteredResult: Result<[String], LocalWordFilter.Error> {
    LocalWordFilter.words(in: language.ownedPracticeLexicon(), matching: criteria)
  }

  private var filteredWords: [String] {
    (try? filteredResult.get()) ?? []
  }

  private var errorMessage: String? {
    guard case .failure(let error) = filteredResult else { return nil }
    return error.errorDescription
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("词表") {
          Picker("语言", selection: $language) {
            ForEach(selectableLanguages, id: \.self) { language in
              Text(language.displayName).tag(language)
            }
          }
          Text("仅筛选 Typebar 自创的离线词表；不会下载或导入第三方词表。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("布局预设") {
          Picker("内置键盘布局", selection: $layout) {
            ForEach(KeyboardLayout.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
          Picker("预设", selection: $preset) {
            ForEach(LocalWordFilterPreset.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          Button("应用到筛选条件") { applyPreset() }
            .disabled(preset.criteria(layout: layout) == nil)
          Text("预设只采用所选内置布局键位的主字符；自定义或系统输入源仍可手填字符筛选。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("筛选") {
          HStack {
            TextField("最短词长", text: $minimumLength)
            TextField("最长词长", text: $maximumLength)
          }
          .textFieldStyle(.roundedBorder)
          TextField("包含任一字符（以空格分隔也可以）", text: $includeCharacters)
          Toggle("仅使用允许字符", isOn: $exactCharactersOnly)
          TextField("排除任一字符", text: $excludeCharacters)
            .disabled(exactCharactersOnly)
          TextField("可选 ICU 正则表达式", text: $regularExpression)
            .disabled(exactCharactersOnly)
          if exactCharactersOnly {
            Text("精确模式会保留完全由“包含”字段字符组成的词，且忽略排除和正则。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section("预览") {
          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
          } else if filteredWords.isEmpty {
            ContentUnavailableView("没有匹配的词", systemImage: "line.3.horizontal.decrease.circle")
          } else {
            LabeledContent("匹配", value: "\(filteredWords.count) 个词")
            Text(filteredWords.prefix(24).joined(separator: " · "))
              .font(.caption)
              .textSelection(.enabled)
          }
        }

        Section {
          Button("替换自定义文本并开始") { apply(appending: false) }
            .disabled(filteredWords.isEmpty)
          Button("追加到自定义文本并开始") { apply(appending: true) }
            .disabled(filteredWords.isEmpty)
        }
      }
      .navigationTitle("词表筛选")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
    .frame(minWidth: 560, minHeight: 520)
  }

  private func apply(appending: Bool) {
    onApply(filteredWords.joined(separator: " "), appending)
    dismiss()
  }

  private func applyPreset() {
    guard let generated = preset.criteria(layout: layout) else { return }
    includeCharacters = generated.includeCharacters
    excludeCharacters = ""
    regularExpression = ""
    exactCharactersOnly = true
  }
}
