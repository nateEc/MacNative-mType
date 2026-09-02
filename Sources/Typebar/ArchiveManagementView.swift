import SwiftData
import SwiftUI

struct ArchiveManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var results: [TestResultRecord]
    @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var presets: [TestPresetRecord]
    @Query(sort: \SavedCustomTextRecord.createdAt, order: .reverse) private var savedTexts: [SavedCustomTextRecord]

    let settings: AppSettings
    @State private var exportDocument: TypebarArchiveDocument?
    @State private var showingImporter = false
    @State private var message: TransferMessage?

    var body: some View {
        NavigationStack {
            Form {
                Section("本机数据") {
                    LabeledContent("已保存成绩", value: "\(results.count) 条")
                    LabeledContent("测试预设", value: "\(presets.count) 个")
                    LabeledContent("自定义文本", value: "\(savedTexts.count) 篇")
                    Text("导出文件不含账户或远程服务数据，可用于迁移到另一台 Mac。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("迁移") {
                    Button("导出本机数据…", systemImage: "square.and.arrow.up") { beginExport() }
                    Button("导入本机数据…", systemImage: "square.and.arrow.down") { showingImporter = true }
                    Text("导入会合并新成绩、预设和自定义文本；相同内容不会重复写入。导入文件中的设置会应用到本机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("数据迁移")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .json,
            defaultFilename: "typebar-backup"
        ) { result in
            switch result {
            case .success:
                message = .init(title: "导出完成", detail: "本机数据已写入所选文件。")
            case .failure(let error):
                message = .init(title: "无法导出", detail: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importArchive(at: url)
            case .failure(let error): message = .init(title: "无法读取文件", detail: error.localizedDescription)
            }
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("好")))
        }
    }

    private func beginExport() {
        let portableResults = results.compactMap(\.portableResult)
        let namedPresets = presets.compactMap { record in
            record.definition.map { NamedPreset(name: record.name, definition: $0) }
        }
        let namedSavedTexts = savedTexts.map { NamedSavedText(title: $0.title, text: $0.text) }
        exportDocument = TypebarArchiveDocument(archive: .init(
            version: TypebarArchive.currentVersion,
            exportedAt: .now,
            settings: settings.snapshot,
            results: portableResults,
            presets: namedPresets,
            savedTexts: namedSavedTexts
        ))
    }

    private func importArchive(at url: URL) {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let archive = try TypebarDataTransfer.importArchive(from: Data(contentsOf: url))
            let summary = try LocalArchiveImport.apply(archive, settings: settings, results: results, presets: presets, savedTexts: savedTexts, modelContext: modelContext)
            message = .init(title: "导入完成", detail: "新增 \(summary.insertedResults) 条成绩、\(summary.insertedPresets) 个预设和 \(summary.insertedSavedTexts) 篇文本，并已应用文件中的设置。")
        } catch {
            message = .init(title: "无法导入", detail: error.localizedDescription)
        }
    }
}

private struct TransferMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}
