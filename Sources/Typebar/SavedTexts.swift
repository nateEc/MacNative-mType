import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum CustomTextPolicy {
    static let maximumLength = 10_000
    /// Only explicitly saved long texts may exceed the ordinary editor/share limit.
    static let maximumLongSavedLength = 128_000
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

    static func isValidSavedText(
        title: String, text: String, longProgress: Int? = nil
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty && trimmedTitle.count <= maximumTitleLength else { return false }
        if longProgress == nil { return isValid(text) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= maximumLongSavedLength,
              text.utf8.count <= maximumLongSavedLength * 4 else { return false }
        var offset = 0
        while offset < text.count {
            let chunk = LongSavedTextProgress.nextChunk(in: text, after: offset)
            guard isValid(chunk) else { return false }
            offset += chunk.count
        }
        return true
    }
}

/// Typebar keeps progress as a character offset rather than copying the
/// reference project's word-array storage. The offset always advances to a
/// fully matched word boundary, so whitespace, line breaks, and the user's
/// original formatting remain intact when a long text resumes.
enum LongSavedTextProgress {
    /// Returns the next complete-word slice without changing any source
    /// whitespace or punctuation. The ordinary test engine still sees a
    /// bounded prompt, even when the saved source spans many slices.
    static func nextChunk(in text: String, after offset: Int) -> String {
        let remaining = remainingText(in: text, after: offset)
        guard !remaining.isEmpty else { return "" }
        if remaining.count <= CustomTextPolicy.maximumLength { return remaining }
        let prefix = String(remaining.prefix(CustomTextPolicy.maximumLength))
        guard let boundary = prefix.lastIndex(where: \.isWhitespace) else { return "" }
        let chunk = String(prefix[...boundary])
        return chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : chunk
    }

    static func offsetAfterCompletingChunk(in text: String, from offset: Int) -> Int {
        let next = normalized(offset, in: text) + nextChunk(in: text, after: offset).count
        return next >= text.count ? 0 : next
    }

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

    init(id: UUID = UUID(), title: String, text: String, longProgress: Int? = nil) {
        self.id = id
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

    let onUse: (SavedCustomTextSelection, Bool) -> Void
    private let tombstones = SavedTextTombstoneStore()
    @State private var importingLongText = false
    @State private var showingImportError = false
    @State private var importError: String?

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
                                            Button("连续输入剩余文本") {
                                                onUse(item.selection, true)
                                                dismiss()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
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
                ToolbarItem(placement: .primaryAction) {
                    Button("导入长文本…", systemImage: "square.and.arrow.down") {
                        importingLongText = true
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importingLongText, allowedContentTypes: [.plainText]) {
                importLongText($0)
            }
            .alert("导入失败", isPresented: $showingImportError) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "无法读取此文件。")
            }
        }
        .frame(minWidth: 500, minHeight: 360)
    }

    private func savedTextButton(_ item: SavedCustomTextRecord) -> some View {
        Button {
            onUse(item.selection, false)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                Text(String(item.text.prefix(160)))
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                tombstones.markDeleted(item.id)
                modelContext.delete(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func resetProgress(for item: SavedCustomTextRecord) {
        item.longProgress = 0
        try? modelContext.save()
    }

    private func importLongText(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let maximumBytes = CustomTextPolicy.maximumLongSavedLength * 4
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > maximumBytes
            {
                throw LongTextImportError.tooLarge
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= maximumBytes {
                let count = min(64_000, maximumBytes + 1 - data.count)
                let chunk = try handle.read(upToCount: count) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
            }
            guard data.count <= maximumBytes else { throw LongTextImportError.tooLarge }
            guard let text = String(data: data, encoding: .utf8) else {
                throw LongTextImportError.invalidEncoding
            }
            let title = String(url.deletingPathExtension().lastPathComponent.prefix(
                CustomTextPolicy.maximumTitleLength))
            guard text.first?.isWhitespace == false,
                  CustomTextPolicy.isValidSavedText(title: title, text: text, longProgress: 0)
            else { throw LongTextImportError.invalidContent }
            let record = SavedCustomTextRecord(title: title, text: text, longProgress: 0)
            modelContext.insert(record)
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(record)
                throw error
            }
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }
}

private enum LongTextImportError: LocalizedError {
    case tooLarge, invalidEncoding, invalidContent

    var errorDescription: String? {
        switch self {
        case .tooLarge: "文件太大；长文本最多 128,000 个字符且不超过 512,000 字节。"
        case .invalidEncoding: "只支持 UTF-8 纯文本文件。"
        case .invalidContent: "文件为空、以空白开头、超出字符上限，或含有无法按完整词边界切分的片段。"
        }
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
