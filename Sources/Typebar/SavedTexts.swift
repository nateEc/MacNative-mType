import Foundation
import SwiftData
import SwiftUI

enum CustomTextPolicy {
    static let maximumLength = 10_000
    static let maximumTitleLength = 80

    static func clamped(_ text: String) -> String {
        String(text.prefix(maximumLength))
    }

    static func isValid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maximumLength
    }

    static func sections(in text: String) -> [String] {
        let values = text.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? [text.trimmingCharacters(in: .whitespacesAndNewlines)] : values
    }

    static func isValidSavedText(title: String, text: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty && trimmedTitle.count <= maximumTitleLength && isValid(text)
    }
}

/// Typebar keeps progress as a character offset rather than copying the
/// reference project's word-array storage. The offset always advances to a
/// fully matched word boundary, so whitespace, line breaks, and the user's
/// original formatting remain intact when a long text resumes.
enum LongSavedTextProgress {
    static func normalized(_ offset: Int, in text: String) -> Int {
        min(max(0, offset), text.count)
    }

    static func remainingText(in text: String, after offset: Int) -> String {
        String(text.dropFirst(normalized(offset, in: text)))
    }

    static func advancedOffset(in text: String, from offset: Int, typed: String) -> Int {
        let normalizedOffset = normalized(offset, in: text)
        let remaining = Array(remainingText(in: text, after: normalizedOffset))
        let typedCharacters = Array(typed)
        var matchingPrefixCount = 0
        while matchingPrefixCount < min(remaining.count, typedCharacters.count),
              remaining[matchingPrefixCount] == typedCharacters[matchingPrefixCount]
        {
            matchingPrefixCount += 1
        }

        var completedPrefixCount = 0
        var cursor = 0
        while cursor < remaining.count {
            while cursor < remaining.count, remaining[cursor].isWhitespace { cursor += 1 }
            let wordStart = cursor
            while cursor < remaining.count, !remaining[cursor].isWhitespace { cursor += 1 }
            guard wordStart < cursor, matchingPrefixCount >= cursor else { break }
            while cursor < remaining.count, remaining[cursor].isWhitespace { cursor += 1 }
            completedPrefixCount = cursor
        }
        return normalizedOffset + completedPrefixCount
    }

    static func progressLabel(in text: String, offset: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return "0 / 0 词" }
        let completed = remainingText(in: text, after: 0)
            .prefix(normalized(offset, in: text))
            .split(whereSeparator: \.isWhitespace)
            .count
        return "\(min(completed, words.count)) / \(words.count) 词"
    }
}

struct SavedCustomTextSelection: Equatable {
    let id: UUID
    let title: String
    let text: String
    let longProgress: Int?

    var isLong: Bool { longProgress != nil }
}

@Model
final class SavedCustomTextRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var text: String
    var createdAt: Date
    /// `nil` identifies an ordinary saved text. A non-nil offset identifies a
    /// long text and is optional to keep existing SwiftData rows compatible.
    var longProgress: Int?

    init(title: String, text: String, longProgress: Int? = nil) {
        id = UUID()
        self.title = title
        self.text = text
        createdAt = .now
        self.longProgress = longProgress.map { LongSavedTextProgress.normalized($0, in: text) }
    }

    var isLong: Bool { longProgress != nil }
    var normalizedLongProgress: Int {
        LongSavedTextProgress.normalized(longProgress ?? 0, in: text)
    }

    var selection: SavedCustomTextSelection {
        .init(id: id, title: title, text: text, longProgress: longProgress)
    }
}

struct SavedTextsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCustomTextRecord.createdAt, order: .reverse) private var savedTexts: [SavedCustomTextRecord]

    let onUse: (SavedCustomTextSelection) -> Void

    private var ordinaryTexts: [SavedCustomTextRecord] { savedTexts.filter { !$0.isLong } }
    private var longTexts: [SavedCustomTextRecord] { savedTexts.filter(\.isLong) }

    var body: some View {
        NavigationStack {
            Group {
                if savedTexts.isEmpty {
                    ContentUnavailableView("还没有保存的文本", systemImage: "text.book.closed", description: Text("在自定义模式中输入内容后，可以把它保存到这里。"))
                } else {
                    List {
                        if !ordinaryTexts.isEmpty {
                            Section("已保存文本") {
                                ForEach(ordinaryTexts) { item in
                                    savedTextButton(item)
                                }
                            }
                        }
                        if !longTexts.isEmpty {
                            Section("保存的长文本") {
                                ForEach(longTexts) { item in
                                    VStack(alignment: .leading, spacing: 7) {
                                        savedTextButton(item)
                                        HStack {
                                            Text(LongSavedTextProgress.progressLabel(
                                                in: item.text, offset: item.normalizedLongProgress))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button("重置进度") { resetProgress(for: item) }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .disabled(item.normalizedLongProgress == 0)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("已保存文本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 360)
    }

    private func savedTextButton(_ item: SavedCustomTextRecord) -> some View {
        Button {
            onUse(item.selection)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                Text(item.text)
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) { modelContext.delete(item) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func resetProgress(for item: SavedCustomTextRecord) {
        item.longProgress = 0
        try? modelContext.save()
    }
}

struct SaveCustomTextView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let text: String
    @State private var title = ""
    @State private var savesLongTextProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("保存自定义文本").font(.title2.weight(.semibold))
            TextField("标题", text: $title)
            Text(text)
                .lineLimit(4)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(text.count) / \(CustomTextPolicy.maximumLength) 个字符")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("作为长文本保存并记住进度", isOn: $savesLongTextProgress)
            Text("长文本会从完整词边界继续；完成时自动回到开头。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!CustomTextPolicy.isValidSavedText(title: title, text: text))
            }
        }
        .padding(28)
        .frame(width: 420)
    }

    private func save() {
        guard CustomTextPolicy.isValidSavedText(title: title, text: text) else { return }
        modelContext.insert(SavedCustomTextRecord(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), text: text,
            longProgress: savesLongTextProgress ? 0 : nil))
        dismiss()
    }
}
