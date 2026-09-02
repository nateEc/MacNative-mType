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

@Model
final class SavedCustomTextRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var text: String
    var createdAt: Date

    init(title: String, text: String) {
        id = UUID()
        self.title = title
        self.text = text
        createdAt = .now
    }
}

struct SavedTextsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCustomTextRecord.createdAt, order: .reverse) private var savedTexts: [SavedCustomTextRecord]

    let onUse: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if savedTexts.isEmpty {
                    ContentUnavailableView("还没有保存的文本", systemImage: "text.book.closed", description: Text("在自定义模式中输入内容后，可以把它保存到这里。"))
                } else {
                    List {
                        ForEach(savedTexts) { item in
                            Button {
                                onUse(item.text)
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
                        }
                        .onDelete(perform: delete)
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

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(savedTexts[index]) }
    }
}

struct SaveCustomTextView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let text: String
    @State private var title = ""

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
        modelContext.insert(SavedCustomTextRecord(title: title.trimmingCharacters(in: .whitespacesAndNewlines), text: text))
        dismiss()
    }
}
