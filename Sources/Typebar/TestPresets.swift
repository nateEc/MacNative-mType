import Foundation
import SwiftData
import SwiftUI

/// Mirrors the official preset configuration groups that have a native setting
/// counterpart. There is intentionally no `.ads` case: Typebar has no ads or
/// ad-preference state to capture.
enum PresetSettingGroup: String, CaseIterable, Codable, Hashable, Identifiable {
    case test
    case behavior
    case input
    case sound
    case caret
    case appearance
    case theme
    case hideElements
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .test: "测试"
        case .behavior: "行为"
        case .input: "输入"
        case .sound: "声音"
        case .caret: "光标"
        case .appearance: "外观"
        case .theme: "主题"
        case .hideElements: "隐藏元素"
        case .hidden: "其他"
        }
    }
}

struct SavedTestPreset: Codable, Equatable {
    var configuration: TestConfiguration
    var quoteID: String?
    var customText: String?
    /// Nil keeps archives made before active tags were added compatible and
    /// leaves the user's current global tags unchanged when applied.
    var activeResultTags: [String]? = nil
    /// New presets retain the native equivalents of the official config
    /// surface. Old archives omit this field and retain their old semantics.
    var settingsSnapshot: AppSettingsSnapshot? = nil
    /// `nil` is a full preset. A non-nil set is a partial preset, including an
    /// empty set imported from malformed external data.
    var settingGroups: Set<PresetSettingGroup>? = nil

    var isPartial: Bool { settingGroups != nil }

    var scopeDescription: String {
        guard let settingGroups else { return "完整预设" }
        guard !settingGroups.isEmpty else { return "部分预设 · 未选择类别" }
        let titles = PresetSettingGroup.allCases.compactMap { group in
            settingGroups.contains(group) ? group.title : nil
        }
        return "部分预设 · \(titles.joined(separator: "、"))"
    }

    func with(settingGroups: Set<PresetSettingGroup>?) -> Self {
        var copy = self
        copy.settingGroups = settingGroups
        return copy
    }

    var summaryDescription: String {
        switch configuration.mode {
        case .time: configuration.isInfinite ? "时间 · 无限" : "时间 · \(Int(configuration.duration ?? 0)) 秒"
        case .words: configuration.isInfinite ? "字数 · 无限" : "字数 · \(configuration.wordLimit ?? 0) 词"
        case .quote: "引语"
        case .zen: "禅"
        case .custom:
            switch configuration.customTextCompletion {
            case .finish: "自定义文本 · 输入完成"
            case .time:
                configuration.isInfinite
                    ? "自定义文本 · 无限循环计时"
                    : "自定义文本 · 循环 \(Int(configuration.duration ?? 0)) 秒"
            case .words:
                configuration.isInfinite
                    ? "自定义文本 · 无限循环字数"
                    : "自定义文本 · 循环 \(configuration.wordLimit ?? 0) 词"
            case .sections: "自定义文本 · \(configuration.customTextSectionLimit ?? 0) 段"
            }
        }
    }
}

@Model
final class TestPresetRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var definitionData: Data
    var createdAt: Date

    init(id: UUID = UUID(), name: String, definition: SavedTestPreset) {
        self.id = id
        self.name = name
        definitionData = (try? JSONEncoder().encode(definition)) ?? Data()
        createdAt = .now
    }

    var definition: SavedTestPreset? {
        try? JSONDecoder().decode(SavedTestPreset.self, from: definitionData)
    }

    func update(name: String, definition: SavedTestPreset? = nil) {
        self.name = name
        if let definition {
            definitionData = (try? JSONEncoder().encode(definition)) ?? definitionData
        }
    }
}

struct PresetLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var presets: [TestPresetRecord]

    let currentPreset: SavedTestPreset
    let onApply: (SavedTestPreset) -> Void
    private let tombstones = PresetTombstoneStore()
    @State private var name = ""
    @State private var isPartial = false
    @State private var selectedGroups = Set(PresetSettingGroup.allCases)
    @State private var editingPreset: TestPresetRecord?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("预设名称", text: $name)
                        Button("保存当前设置") { save() }
                            .disabled(!canSave)
                    }
                    PresetScopeSelector(isPartial: $isPartial, selectedGroups: $selectedGroups)
                }
                .padding()

                if presets.isEmpty {
                    ContentUnavailableView(
                        "还没有预设", systemImage: "slider.horizontal.3",
                        description: Text("设置好一轮练习后，可将完整设置或选定的设置类别保存为预设。"))
                } else {
                    List {
                        ForEach(presets) { preset in
                            HStack(spacing: 10) {
                                Button {
                                    guard let definition = preset.definition else { return }
                                    onApply(definition)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.name)
                                        Text(preset.definition?.summaryDescription ?? "无法读取的预设")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let definition = preset.definition {
                                            Text(definition.scopeDescription)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.tint)
                                }
                                .buttonStyle(.plain)
                                .disabled(preset.definition?.settingGroups?.isEmpty == true)

                                Menu {
                                    Button("编辑") { editingPreset = preset }
                                    Button("删除", role: .destructive) { delete(preset) }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
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
        .frame(minWidth: 520, minHeight: 420)
        .sheet(item: $editingPreset) { preset in
            PresetEditorView(record: preset, currentPreset: currentPreset)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!isPartial || !selectedGroups.isEmpty)
    }

    private func save() {
        let definition = currentPreset.with(
            settingGroups: isPartial ? selectedGroups : nil)
        modelContext.insert(TestPresetRecord(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), definition: definition))
        name = ""
        isPartial = false
        selectedGroups = Set(PresetSettingGroup.allCases)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            delete(presets[index])
        }
    }

    private func delete(_ preset: TestPresetRecord) {
        tombstones.markDeleted(preset.id)
        modelContext.delete(preset)
    }
}

private struct PresetScopeSelector: View {
    @Binding var isPartial: Bool
    @Binding var selectedGroups: Set<PresetSettingGroup>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("预设范围", selection: $isPartial) {
                Text("完整").tag(false)
                Text("部分").tag(true)
            }
            .pickerStyle(.segmented)

            if isPartial {
                Text("应用时只更改已选择的类别。至少选择一项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                    ForEach(PresetSettingGroup.allCases) { group in
                        Toggle(group.title, isOn: binding(for: group))
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private func binding(for group: PresetSettingGroup) -> Binding<Bool> {
        .init(
            get: { selectedGroups.contains(group) },
            set: { isSelected in
                if isSelected {
                    selectedGroups.insert(group)
                } else {
                    selectedGroups.remove(group)
                }
            })
    }
}

private struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let record: TestPresetRecord
    let currentPreset: SavedTestPreset
    @State private var name: String
    @State private var updateConfiguration = false
    @State private var isPartial: Bool
    @State private var selectedGroups: Set<PresetSettingGroup>

    init(record: TestPresetRecord, currentPreset: SavedTestPreset) {
        self.record = record
        self.currentPreset = currentPreset
        let definition = record.definition
        _name = State(initialValue: record.name)
        _isPartial = State(initialValue: definition?.isPartial ?? false)
        _selectedGroups = State(initialValue: definition?.settingGroups ?? Set(PresetSettingGroup.allCases))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("预设名称", text: $name)
            Toggle("将设置更新为当前状态", isOn: $updateConfiguration)
            if updateConfiguration {
                PresetScopeSelector(isPartial: $isPartial, selectedGroups: $selectedGroups)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!updateConfiguration || !isPartial || !selectedGroups.isEmpty)
    }

    private func save() {
        let definition: SavedTestPreset? = updateConfiguration
            ? currentPreset.with(settingGroups: isPartial ? selectedGroups : nil)
            : nil
        record.update(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), definition: definition)
        dismiss()
    }
}
