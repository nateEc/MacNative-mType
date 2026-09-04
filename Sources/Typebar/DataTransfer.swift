import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Produces a portable, spreadsheet-friendly view of local result metadata.
///
/// The CSV intentionally omits prompts and replay events. Those fields can
/// contain user-authored text, while the exported metrics are sufficient for
/// analysis outside Typebar without exposing that content by default.
enum ResultCSVExport {
    static let columns = [
        "id",
        "outcome",
        "wpm",
        "raw_wpm",
        "accuracy_percent",
        "typing_consistency_percent",
        "key_consistency_percent",
        "correct_characters",
        "typed_characters",
        "errors",
        "mode",
        "duration_seconds",
        "word_limit",
        "language",
        "punctuation",
        "numbers",
        "difficulty",
        "modifiers",
        "tags",
        "started_at",
        "finished_at",
        "elapsed_seconds",
        "afk_seconds",
        "engaged_seconds",
    ]

    static func data(for results: [CompletedTestResult]) -> Data {
        Data(csvString(for: results).utf8)
    }

    static func csvString(for results: [CompletedTestResult]) -> String {
        ([columns] + results.map(row(for:)))
            .map { $0.map(escaped).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func filename(for date: Date) -> String {
        "typebar-results-\(filenameFormatter.string(from: date)).csv"
    }

    private static func row(for result: CompletedTestResult) -> [String] {
        let consistency = ResultConsistencyPolicy.metrics(
            events: result.replayEvents, duration: result.elapsedDuration)
        let configuration = result.configuration
        return [
            result.id.uuidString.lowercased(),
            result.outcome.rawValue,
            String(result.wpm),
            String(result.rawWpm),
            String(result.accuracy),
            decimal(consistency.typing),
            decimal(consistency.key),
            String(result.correctCharacterCount),
            String(result.typedCharacterCount),
            String(result.errorCount),
            configuration.mode.rawValue,
            configuration.duration.map(decimal) ?? "",
            configuration.wordLimit.map(String.init) ?? "",
            configuration.language.rawValue,
            String(configuration.contentOptions.includePunctuation),
            String(configuration.contentOptions.includeNumbers),
            configuration.difficulty.rawValue,
            configuration.modifiers.map(\.rawValue).joined(separator: ";"),
            ResultTagPolicy.normalized(result.tags).joined(separator: ";"),
            iso8601Date(result.startedAt),
            iso8601Date(result.finishedAt),
            decimal(result.elapsedDuration),
            decimal(result.afkDuration),
            decimal(result.engagedDuration),
        ]
    }

    private static func escaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func iso8601Date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

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
    /// `nil` preserves the ordinary saved-text behavior used by archives made
    /// before long-text progress tracking was added.
    let longProgress: Int?

    init(title: String, text: String, longProgress: Int? = nil) {
        self.title = title
        self.text = text
        self.longProgress = longProgress.map { LongSavedTextProgress.normalized($0, in: text) }
    }

    private enum CodingKeys: String, CodingKey {
        case title, text, longProgress
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try values.decode(String.self, forKey: .title)
        let decodedText = try values.decode(String.self, forKey: .text)
        let decodedProgress = try values.decodeIfPresent(Int.self, forKey: .longProgress)
        title = decodedTitle
        text = decodedText
        longProgress = decodedProgress.map {
            LongSavedTextProgress.normalized($0, in: decodedText)
        }
    }
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
            existing: savedTexts.map {
                NamedSavedText(title: $0.title, text: $0.text, longProgress: $0.longProgress)
            }
        )

        for result in newResults { modelContext.insert(TestResultRecord(result: result)) }
        for preset in newPresets { modelContext.insert(TestPresetRecord(name: preset.name, definition: preset.definition)) }
        for savedText in newSavedTexts {
            modelContext.insert(SavedCustomTextRecord(
                title: savedText.title, text: savedText.text, longProgress: savedText.longProgress))
        }
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
