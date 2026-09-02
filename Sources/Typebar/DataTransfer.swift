import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TypebarArchive: Codable, Equatable {
    static let currentVersion = 2
    let version: Int
    let exportedAt: Date
    let settings: AppSettingsSnapshot
    let results: [CompletedTestResult]
    let presets: [NamedPreset]
    let savedTexts: [NamedSavedText]

    init(version: Int = TypebarArchive.currentVersion, exportedAt: Date, settings: AppSettingsSnapshot, results: [CompletedTestResult], presets: [NamedPreset], savedTexts: [NamedSavedText] = []) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.results = results
        self.presets = presets
        self.savedTexts = savedTexts
    }

    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, settings, results, presets, savedTexts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        settings = try values.decode(AppSettingsSnapshot.self, forKey: .settings)
        results = try values.decode([CompletedTestResult].self, forKey: .results)
        presets = try values.decode([NamedPreset].self, forKey: .presets)
        savedTexts = try values.decodeIfPresent([NamedSavedText].self, forKey: .savedTexts) ?? []
    }
}

struct NamedPreset: Codable, Equatable {
    let name: String
    let definition: SavedTestPreset
}

struct NamedSavedText: Codable, Equatable {
    let title: String
    let text: String
}

enum DataTransferError: Error, Equatable {
    case unsupportedVersion(Int)
}

enum TypebarDataTransfer {
    static func exportArchive(settings: AppSettingsSnapshot, results: [CompletedTestResult], presets: [NamedPreset], savedTexts: [NamedSavedText] = [], at date: Date = .now) throws -> Data {
        try JSONEncoder.typebar.encode(TypebarArchive(version: TypebarArchive.currentVersion, exportedAt: date, settings: settings, results: results, presets: presets, savedTexts: savedTexts))
    }

    static func importArchive(from data: Data) throws -> TypebarArchive {
        let archive = try JSONDecoder.typebar.decode(TypebarArchive.self, from: data)
        guard (1...TypebarArchive.currentVersion).contains(archive.version) else { throw DataTransferError.unsupportedVersion(archive.version) }
        return archive
    }
}

enum TypebarArchiveMerge {
    static func resultsToInsert(from archive: TypebarArchive, existingIDs: Set<UUID>) -> [CompletedTestResult] {
        archive.results.filter { !existingIDs.contains($0.id) }
    }

    static func presetsToInsert(from archive: TypebarArchive, existing: [NamedPreset]) -> [NamedPreset] {
        archive.presets.filter { !existing.contains($0) }
    }

    static func savedTextsToInsert(from archive: TypebarArchive, existing: [NamedSavedText]) -> [NamedSavedText] {
        archive.savedTexts.filter {
            CustomTextPolicy.isValidSavedText(title: $0.title, text: $0.text) && !existing.contains($0)
        }
    }
}

struct ArchiveImportSummary: Equatable {
    let insertedResults: Int
    let insertedPresets: Int
    let insertedSavedTexts: Int
}

@MainActor
enum LocalArchiveImport {
    static func apply(
        _ archive: TypebarArchive,
        settings: AppSettings,
        results: [TestResultRecord],
        presets: [TestPresetRecord],
        savedTexts: [SavedCustomTextRecord],
        modelContext: ModelContext
    ) throws -> ArchiveImportSummary {
        let newResults = TypebarArchiveMerge.resultsToInsert(from: archive, existingIDs: Set(results.map(\.id)))
        let existingPresets = presets.compactMap { record in
            record.definition.map { NamedPreset(name: record.name, definition: $0) }
        }
        let newPresets = TypebarArchiveMerge.presetsToInsert(from: archive, existing: existingPresets)
        let newSavedTexts = TypebarArchiveMerge.savedTextsToInsert(
            from: archive,
            existing: savedTexts.map { NamedSavedText(title: $0.title, text: $0.text) }
        )

        for result in newResults { modelContext.insert(TestResultRecord(result: result)) }
        for preset in newPresets { modelContext.insert(TestPresetRecord(name: preset.name, definition: preset.definition)) }
        for savedText in newSavedTexts { modelContext.insert(SavedCustomTextRecord(title: savedText.title, text: savedText.text)) }
        settings.apply(archive.settings)
        try modelContext.save()
        return .init(insertedResults: newResults.count, insertedPresets: newPresets.count, insertedSavedTexts: newSavedTexts.count)
    }
}

struct TypebarArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let archive: TypebarArchive

    init(archive: TypebarArchive) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try TypebarDataTransfer.importArchive(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try TypebarDataTransfer.exportArchive(
            settings: archive.settings,
            results: archive.results,
            presets: archive.presets,
            savedTexts: archive.savedTexts,
            at: archive.exportedAt
        ))
    }
}

private extension JSONEncoder {
    static var typebar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var typebar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
