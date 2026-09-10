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
        "matched_characters",
        "incorrect_characters",
        "extra_characters",
        "missed_characters",
        "key_duration_average_ms",
        "key_duration_sd_ms",
        "key_duration_samples",
        "key_spacing_average_ms",
        "key_spacing_sd_ms",
        "key_spacing_samples",
        "key_overlap_ms",
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
        "restart_count",
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
        let keyDurationStats = result.keyDurationStats
        let keySpacingStats = result.keySpacingStats
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
            String(result.characterStats.matched),
            String(result.characterStats.incorrect),
            String(result.characterStats.extra),
            String(result.characterStats.missed),
            keyDurationStats.map { decimal($0.averageMilliseconds) } ?? "",
            keyDurationStats.map { decimal($0.standardDeviationMilliseconds) } ?? "",
            keyDurationStats.map { String($0.sampleCount) } ?? "0",
            keySpacingStats.map { decimal($0.averageMilliseconds) } ?? "",
            keySpacingStats.map { decimal($0.standardDeviationMilliseconds) } ?? "",
            keySpacingStats.map { String($0.sampleCount) } ?? "0",
            decimal(result.keyOverlapDuration * 1_000),
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
            String(result.restartCount),
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

enum RemoteResultCSVExportError: Error, Equatable {
    case invalidPageSize
    case changedDuringExport
}

/// Exports only the result metadata already exposed by the self-hosted service.
/// Prompt text and replay events are absent from `RemoteAccountResult`, so they
/// cannot accidentally enter this CSV path.
enum RemoteResultCSVExport {
    static let columns = [
        "id", "mode", "duration_seconds", "word_limit", "language", "wpm", "raw_wpm",
        "accuracy_percent", "consistency_percent", "errors", "event_count", "tags",
        "started_at", "finished_at",
    ]

    @MainActor
    static func loadAll(
        pageSize: Int = 1_000,
        loadPage: (_ offset: Int, _ limit: Int) async throws -> RemoteAccountResultPage
    ) async throws -> [RemoteAccountResult] {
        guard (1...1_000).contains(pageSize) else {
            throw RemoteResultCSVExportError.invalidPageSize
        }
        var offset = 0
        var expectedTotal: Int?
        var loaded: [RemoteAccountResult] = []
        var loadedIDs: Set<UUID> = []

        repeat {
            let page = try await loadPage(offset, pageSize)
            guard page.total >= 0, page.results.count <= pageSize else {
                throw RemoteResultCSVExportError.changedDuringExport
            }
            if let expectedTotal {
                guard page.total == expectedTotal else {
                    throw RemoteResultCSVExportError.changedDuringExport
                }
            } else {
                expectedTotal = page.total
            }
            guard !page.results.isEmpty || offset == page.total else {
                throw RemoteResultCSVExportError.changedDuringExport
            }
            for result in page.results {
                guard loadedIDs.insert(result.id).inserted else {
                    throw RemoteResultCSVExportError.changedDuringExport
                }
                loaded.append(result)
            }
            offset += page.results.count
            guard offset <= page.total else {
                throw RemoteResultCSVExportError.changedDuringExport
            }
        } while offset < (expectedTotal ?? 0)

        guard loaded.count == expectedTotal else {
            throw RemoteResultCSVExportError.changedDuringExport
        }
        return loaded
    }

    static func data(for results: [RemoteAccountResult]) -> Data {
        Data(csvString(for: results).utf8)
    }

    static func csvString(for results: [RemoteAccountResult]) -> String {
        ([columns] + results.map(row(for:)))
            .map { $0.map(escaped).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func filename(for date: Date) -> String {
        "typebar-server-results-\(filenameFormatter.string(from: date)).csv"
    }

    private static func row(for result: RemoteAccountResult) -> [String] {
        [
            result.id.uuidString.lowercased(), result.mode,
            result.durationSeconds.map(String.init) ?? "", result.wordLimit.map(String.init) ?? "",
            result.language, String(result.wpm), String(result.rawWpm), String(result.accuracy),
            decimal(result.consistency), String(result.errorCount), String(result.eventCount),
            result.tags.joined(separator: ";"), iso8601Date(result.startedAt),
            iso8601Date(result.finishedAt),
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
    static let currentVersion = 3
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

struct TypebarTestParameterMemory: Codable, Equatable {
    static let defaults = TypebarTestParameterMemory(
        duration: 30,
        wordLimit: 25,
        customTextDuration: 30,
        customTextWordLimit: 25,
        customTextSectionLimit: 1)

    let duration: Int
    let wordLimit: Int
    let customTextDuration: Int
    let customTextWordLimit: Int
    let customTextSectionLimit: Int

    static func legacyDefaults(configuration: TestConfiguration) -> Self {
        var result = defaults
        switch configuration.mode {
        case .time:
            if let duration = safeInteger(configuration.duration) {
                result = result.with(duration: duration)
            }
        case .words:
            if let wordLimit = configuration.wordLimit {
                result = result.with(wordLimit: wordLimit)
            }
        case .custom:
            switch configuration.customTextCompletion {
            case .time:
                if let duration = safeInteger(configuration.duration) {
                    result = result.with(customTextDuration: duration)
                }
            case .words:
                if let wordLimit = configuration.wordLimit {
                    result = result.with(customTextWordLimit: wordLimit)
                }
            case .sections:
                if let sectionLimit = configuration.customTextSectionLimit {
                    result = result.with(customTextSectionLimit: sectionLimit)
                }
            case .finish:
                break
            }
        case .quote, .zen:
            break
        }
        return result
    }

    private static func safeInteger(_ value: TimeInterval?) -> Int? {
        guard let value, value.isFinite, value >= 0,
              value <= Double(OfficialTestLimitInput.maximumValue),
              value.rounded(.towardZero) == value
        else { return nil }
        return Int(value)
    }

    private func with(
        duration: Int? = nil,
        wordLimit: Int? = nil,
        customTextDuration: Int? = nil,
        customTextWordLimit: Int? = nil,
        customTextSectionLimit: Int? = nil
    ) -> Self {
        .init(
            duration: duration ?? self.duration,
            wordLimit: wordLimit ?? self.wordLimit,
            customTextDuration: customTextDuration ?? self.customTextDuration,
            customTextWordLimit: customTextWordLimit ?? self.customTextWordLimit,
            customTextSectionLimit: customTextSectionLimit ?? self.customTextSectionLimit)
    }
}

struct TypebarSettingsDocument: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let settings: AppSettingsSnapshot
    let configuration: TestConfiguration
    let layoutFluidLayouts: [KeyboardLayout]
    let testParameterMemory: TypebarTestParameterMemory

    init(
        version: Int = TypebarSettingsDocument.currentVersion,
        settings: AppSettingsSnapshot,
        configuration: TestConfiguration,
        layoutFluidLayouts: [KeyboardLayout],
        testParameterMemory: TypebarTestParameterMemory
    ) {
        self.version = version
        self.settings = settings
        self.configuration = configuration.with(challengeID: nil)
        self.layoutFluidLayouts = LayoutFluidPolicy.normalizedLayouts(layoutFluidLayouts)
        self.testParameterMemory = testParameterMemory
    }

    private enum CodingKeys: String, CodingKey {
        case version, settings, configuration, layoutFluidLayouts, testParameterMemory
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        settings = try values.decode(AppSettingsSnapshot.self, forKey: .settings)
        configuration = try values.decode(TestConfiguration.self, forKey: .configuration)
        layoutFluidLayouts = try values.decode([KeyboardLayout].self, forKey: .layoutFluidLayouts)
        if version == Self.currentVersion {
            testParameterMemory = try values.decode(
                TypebarTestParameterMemory.self, forKey: .testParameterMemory)
        } else {
            testParameterMemory = try values.decodeIfPresent(
                TypebarTestParameterMemory.self, forKey: .testParameterMemory)
                ?? .legacyDefaults(configuration: configuration)
        }
    }
}

enum SettingsJSONCommandError: Error, Equatable, LocalizedError {
    case emptyDocument
    case invalidDocument
    case invalidConfiguration
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "请粘贴 Typebar 设置 JSON。"
        case .invalidDocument:
            "无法读取这份设置 JSON；请确认内容完整且格式正确。"
        case .invalidConfiguration:
            "设置 JSON 包含不支持的测试模式或数值范围。"
        case .unsupportedVersion(let version):
            "不支持设置 JSON 版本 \(version)。请使用当前版本的 Typebar 导出。"
        }
    }
}

enum SettingsJSONCommandCodec {
    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    static func export(
        settings: AppSettingsSnapshot,
        configuration: TestConfiguration,
        layoutFluidLayouts: [KeyboardLayout],
        testParameterMemory: TypebarTestParameterMemory
    ) throws -> String {
        let data = try JSONEncoder.typebar.encode(TypebarSettingsDocument(
            settings: settings, configuration: configuration,
            layoutFluidLayouts: layoutFluidLayouts,
            testParameterMemory: testParameterMemory))
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String) throws -> TypebarSettingsDocument {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SettingsJSONCommandError.emptyDocument
        }
        let data = Data(json.utf8)
        let version: Int
        do {
            version = try JSONDecoder.typebar.decode(VersionEnvelope.self, from: data).version
        } catch {
            throw SettingsJSONCommandError.invalidDocument
        }
        guard (1...TypebarSettingsDocument.currentVersion).contains(version) else {
            throw SettingsJSONCommandError.unsupportedVersion(version)
        }
        let decoded: TypebarSettingsDocument
        do {
            decoded = try JSONDecoder.typebar.decode(TypebarSettingsDocument.self, from: data)
        } catch {
            throw SettingsJSONCommandError.invalidDocument
        }
        guard SettingsJSONConfigurationPolicy.isValid(decoded.configuration),
              SettingsJSONConfigurationPolicy.isValid(decoded.testParameterMemory)
        else {
            throw SettingsJSONCommandError.invalidConfiguration
        }
        return TypebarSettingsDocument(
            version: decoded.version,
            settings: decoded.settings,
            configuration: decoded.configuration,
            layoutFluidLayouts: decoded.layoutFluidLayouts,
            testParameterMemory: decoded.testParameterMemory)
    }
}

enum SettingsJSONConfigurationPolicy {
    static func isValid(_ memory: TypebarTestParameterMemory) -> Bool {
        isValidLimit(memory.duration)
            && isValidLimit(memory.wordLimit)
            && isValidLimit(memory.customTextDuration)
            && isValidLimit(memory.customTextWordLimit)
            && (1...OfficialTestLimitInput.maximumValue).contains(memory.customTextSectionLimit)
    }

    static func isValid(_ configuration: TestConfiguration) -> Bool {
        switch configuration.mode {
        case .time:
            guard let duration = configuration.duration,
                  isValidDuration(duration), configuration.wordLimit == nil
            else { return false }
        case .words:
            guard let wordLimit = configuration.wordLimit,
                  isValidLimit(wordLimit), configuration.duration == nil
            else { return false }
        case .quote, .zen:
            guard configuration.duration == nil, configuration.wordLimit == nil else { return false }
        case .custom:
            switch configuration.customTextCompletion {
            case .finish:
                guard configuration.duration == nil, configuration.wordLimit == nil else { return false }
            case .time:
                guard let duration = configuration.duration,
                      isValidDuration(duration), configuration.wordLimit == nil
                else { return false }
            case .words:
                guard let wordLimit = configuration.wordLimit,
                      isValidLimit(wordLimit), configuration.duration == nil
                else { return false }
            case .sections:
                guard let sectionLimit = configuration.customTextSectionLimit,
                      (1...OfficialTestLimitInput.maximumValue).contains(sectionLimit),
                      configuration.duration == nil, configuration.wordLimit == nil
                else { return false }
            }
        }
        return true
    }

    private static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite
            && duration >= 0
            && duration.rounded(.towardZero) == duration
            && duration <= Double(OfficialTestLimitInput.maximumValue)
    }

    private static func isValidLimit(_ value: Int) -> Bool {
        (0...OfficialTestLimitInput.maximumValue).contains(value)
    }
}

@MainActor
enum SettingsJSONCommandImport {
    @discardableResult
    static func apply(_ json: String, to settings: AppSettings) throws -> TypebarSettingsDocument {
        let document = try SettingsJSONCommandCodec.decode(json)
        settings.apply(document.settings)
        settings.layoutFluidLayouts = document.layoutFluidLayouts
        return document
    }
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

/// Resolves an archive version race without discarding either device's
/// user-authored content. Scalar settings remain local; remote collections are
/// added, and colliding identities receive a new identity and a visible label.
enum SyncConflictKind: String, Codable, Equatable, Sendable {
    case customTheme
    case customKeyboardLayout
    case preset
    case savedText

    var displayName: String {
        switch self {
        case .customTheme: "自定义主题"
        case .customKeyboardLayout: "自定义键盘布局"
        case .preset: "测试预设"
        case .savedText: "自定义文本"
        }
    }

    var systemImage: String {
        switch self {
        case .customTheme: "paintpalette"
        case .customKeyboardLayout: "keyboard"
        case .preset: "slider.horizontal.3"
        case .savedText: "doc.text"
        }
    }
}

struct SyncConflictCopy: Codable, Equatable, Sendable {
    let kind: SyncConflictKind
    let displayName: String
}

struct TypebarArchiveConflictMergeResult: Equatable {
    let archive: TypebarArchive
    let conflicts: [SyncConflictCopy]
}

enum TypebarArchiveConflictMerge {
    private static let conflictSuffix = "（同步冲突）"

    static func merge(
        local: TypebarArchive,
        remote: TypebarArchive,
        makeID: () -> UUID = UUID.init
    ) -> TypebarArchive {
        mergeWithReport(local: local, remote: remote, makeID: makeID).archive
    }

    static func mergeWithReport(
        local: TypebarArchive,
        remote: TypebarArchive,
        makeID: () -> UUID = UUID.init
    ) -> TypebarArchiveConflictMergeResult {
        var settings = local.settings
        var conflicts: [SyncConflictCopy] = []
        var occupiedIDs = Set(settings.customThemes.map(\.id))
        occupiedIDs.formUnion(settings.customKeyboardLayouts.map(\.id))
        var remappedThemeIDs: [UUID: UUID] = [:]

        for remoteTheme in remote.settings.customThemes {
            if let localTheme = settings.customThemes.first(where: { $0.id == remoteTheme.id }) {
                guard localTheme != remoteTheme else { continue }
                let copy = copyTheme(
                    remoteTheme,
                    id: freshID(occupied: &occupiedIDs, makeID: makeID),
                    name: conflictName(
                        for: remoteTheme.name, occupied: Set(settings.customThemes.map(\.name)),
                        maximumLength: 40))
                remappedThemeIDs[remoteTheme.id] = copy.id
                settings.customThemes.append(copy)
                conflicts.append(.init(kind: .customTheme, displayName: copy.name))
            } else {
                var copy = remoteTheme
                occupiedIDs.insert(copy.id)
                if settings.customThemes.contains(where: { $0.name == copy.name }) {
                    copy.name = conflictName(
                        for: copy.name, occupied: Set(settings.customThemes.map(\.name)),
                        maximumLength: 40)
                    conflicts.append(.init(kind: .customTheme, displayName: copy.name))
                }
                settings.customThemes.append(copy)
            }
        }

        for remoteLayout in remote.settings.customKeyboardLayouts {
            if let localLayout = settings.customKeyboardLayouts.first(where: { $0.id == remoteLayout.id }) {
                guard localLayout != remoteLayout else { continue }
                var copy = remoteLayout
                copy.id = freshID(occupied: &occupiedIDs, makeID: makeID)
                copy.name = conflictName(
                    for: copy.name, occupied: Set(settings.customKeyboardLayouts.map(\.name)),
                    maximumLength: 40)
                settings.customKeyboardLayouts.append(copy)
                conflicts.append(.init(kind: .customKeyboardLayout, displayName: copy.name))
            } else {
                var copy = remoteLayout
                occupiedIDs.insert(copy.id)
                if settings.customKeyboardLayouts.contains(where: { $0.name == copy.name }) {
                    copy.name = conflictName(
                        for: copy.name, occupied: Set(settings.customKeyboardLayouts.map(\.name)),
                        maximumLength: 40)
                    conflicts.append(.init(kind: .customKeyboardLayout, displayName: copy.name))
                }
                settings.customKeyboardLayouts.append(copy)
            }
        }

        let remoteFavorites = remote.settings.favoriteThemeIDs.map { identifier in
            guard identifier.hasPrefix("custom:") else { return identifier }
            let rawID = String(identifier.dropFirst("custom:".count))
            guard let id = UUID(uuidString: rawID), let remapped = remappedThemeIDs[id] else {
                return identifier
            }
            return ThemeFavoritePolicy.customID(for: remapped)
        }
        settings.favoriteThemeIDs = ThemeFavoritePolicy.normalized(
            settings.favoriteThemeIDs + remoteFavorites,
            customThemes: settings.customThemes)

        var presets = local.presets
        for remotePreset in remote.presets where !presets.contains(remotePreset) {
            if presets.contains(where: { $0.name == remotePreset.name }) {
                let name = conflictName(for: remotePreset.name, occupied: Set(presets.map(\.name)))
                presets.append(.init(name: name, definition: remotePreset.definition))
                conflicts.append(.init(kind: .preset, displayName: name))
            } else {
                presets.append(remotePreset)
            }
        }

        var savedTexts = local.savedTexts
        for remoteText in remote.savedTexts
        where CustomTextPolicy.isValidSavedText(title: remoteText.title, text: remoteText.text)
            && !savedTexts.contains(remoteText)
        {
            if savedTexts.contains(where: { $0.title == remoteText.title }) {
                let title = conflictName(
                    for: remoteText.title, occupied: Set(savedTexts.map(\.title)),
                    maximumLength: CustomTextPolicy.maximumTitleLength)
                savedTexts.append(.init(
                    title: title,
                    text: remoteText.text,
                    longProgress: remoteText.longProgress))
                conflicts.append(.init(kind: .savedText, displayName: title))
            } else {
                savedTexts.append(remoteText)
            }
        }

        return .init(
            archive: .init(
                version: max(local.version, remote.version),
                exportedAt: max(local.exportedAt, remote.exportedAt),
                settings: settings,
                results: local.results + remote.results.filter { remoteResult in
                    !local.results.contains(where: { $0.id == remoteResult.id })
                },
                presets: presets,
                savedTexts: savedTexts),
            conflicts: conflicts)
    }

    private static func freshID(occupied: inout Set<UUID>, makeID: () -> UUID) -> UUID {
        var candidate = makeID()
        while occupied.contains(candidate) { candidate = makeID() }
        occupied.insert(candidate)
        return candidate
    }

    private static func copyTheme(
        _ theme: CustomThemeDefinition, id: UUID, name: String
    ) -> CustomThemeDefinition {
        .init(
            id: id, name: name, background: theme.background, panel: theme.panel,
            accent: theme.accent, text: theme.text, secondaryText: theme.secondaryText,
            error: theme.error, extraInput: theme.extraInput, caret: theme.caret,
            fadedText: theme.fadedText, colorfulError: theme.colorfulError,
            colorfulExtraInput: theme.colorfulExtraInput, prefersDark: theme.prefersDark)
    }

    private static func conflictName(
        for name: String, occupied: Set<String>, maximumLength: Int? = nil
    ) -> String {
        func candidate(index: Int) -> String {
            let suffix = index == 1 ? conflictSuffix : "（同步冲突 \(index)）"
            guard let maximumLength else { return name + suffix }
            return String(name.prefix(max(0, maximumLength - suffix.count))) + suffix
        }

        var index = 1
        while occupied.contains(candidate(index: index)) { index += 1 }
        return candidate(index: index)
    }
}

struct SyncConflictAuditEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let occurredAt: Date
    let kind: SyncConflictKind
    let displayName: String
}

/// Keeps a small local record of conflict copies without retaining archive
/// payloads, credentials, result details, or user-authored text bodies.
final class SyncConflictAuditStore {
    private static let keyPrefix = "remoteAccount.syncConflictAudit.v1"
    private let defaults: UserDefaults
    private let capacity: Int

    init(defaults: UserDefaults = .standard, capacity: Int = 50) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
    }

    static func storageKey(for scope: ResultPublicationScope) -> String {
        "\(keyPrefix).\(scope.serverID).\(scope.userID.uuidString.lowercased())"
    }

    func entries(for scope: ResultPublicationScope) -> [SyncConflictAuditEntry] {
        guard let data = defaults.data(forKey: Self.storageKey(for: scope)),
            let entries = try? JSONDecoder().decode([SyncConflictAuditEntry].self, from: data)
        else { return [] }
        return Array(entries.prefix(capacity))
    }

    func append(_ conflicts: [SyncConflictCopy], for scope: ResultPublicationScope, at date: Date = .now) {
        guard !conflicts.isEmpty else { return }
        let additions = conflicts.reversed().map {
            SyncConflictAuditEntry(
                id: UUID(), occurredAt: date, kind: $0.kind,
                displayName: String($0.displayName.prefix(80)))
        }
        let updated = Array((additions + entries(for: scope)).prefix(capacity))
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: Self.storageKey(for: scope))
    }

    func clear(for scope: ResultPublicationScope) {
        defaults.removeObject(forKey: Self.storageKey(for: scope))
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
