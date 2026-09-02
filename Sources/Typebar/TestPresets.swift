import Foundation
import SwiftData
import SwiftUI

struct SavedTestPreset: Codable, Equatable {
    var configuration: TestConfiguration
    var quoteID: String?
    var customText: String?
}

@Model
final class TestPresetRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var definitionData: Data
    var createdAt: Date

    init(name: String, definition: SavedTestPreset) {
        id = UUID()
        self.name = name
        definitionData = (try? JSONEncoder().encode(definition)) ?? Data()
        createdAt = .now
    }

    var definition: SavedTestPreset? {
        try? JSONDecoder().decode(SavedTestPreset.self, from: definitionData)
    }
}

struct PresetLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var presets: [TestPresetRecord]

    let currentPreset: SavedTestPreset
    let onApply: (SavedTestPreset) -> Void
    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("预设名称", text: $name)
                    Button("保存当前设置") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()

                if presets.isEmpty {
                    ContentUnavailableView("还没有预设", systemImage: "slider.horizontal.3", description: Text("设置好一轮练习后，把它保存为预设。"))
                } else {
                    List {
                        ForEach(presets) { preset in
                            Button {
                                guard let definition = preset.definition else { return }
                                onApply(definition)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.name)
                                        Text(summary(for: preset.definition))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("测试预设")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 360)
    }

    private func save() {
        modelContext.insert(TestPresetRecord(name: name.trimmingCharacters(in: .whitespacesAndNewlines), definition: currentPreset))
        name = ""
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(presets[index]) }
    }

    private func summary(for preset: SavedTestPreset?) -> String {
        guard let preset else { return "无法读取的预设" }
        return switch preset.configuration.mode {
        case .time: "时间 · \(Int(preset.configuration.duration ?? 0)) 秒"
        case .words: "字数 · \(preset.configuration.wordLimit ?? 0) 词"
        case .quote: "引语"
        case .zen: "禅"
        case .custom:
            switch preset.configuration.customTextCompletion {
            case .finish: "自定义文本 · 输入完成"
            case .time: "自定义文本 · 循环 \(Int(preset.configuration.duration ?? 0)) 秒"
            case .words: "自定义文本 · 循环 \(preset.configuration.wordLimit ?? 0) 词"
            case .sections: "自定义文本 · \(preset.configuration.customTextSectionLimit ?? 0) 段"
            }
        }
    }
}
