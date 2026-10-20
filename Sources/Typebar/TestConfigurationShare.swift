import Foundation
import SwiftUI

enum TestConfigurationShareError: Error, Equatable, LocalizedError {
    case invalidLink
    case invalidPayload
    case unsupportedVersion(Int)
    case invalidConfiguration
    case thresholdSourceNotReady

    var errorDescription: String? {
        switch self {
        case .invalidLink: "这不是有效的 Typebar 测试链接。"
        case .invalidPayload: "测试链接的数据无法读取。"
        case .unsupportedVersion: "此测试链接版本暂不受支持。"
        case .invalidConfiguration: "测试链接包含不支持的配置范围。"
        case .thresholdSourceNotReady: "链接已读取，但完整阈值设置尚未接入，暂不能应用。"
        }
    }
}

enum TestConfigurationShare {
    private static let scheme = "typebar"
    private static let host = "test"
    private static let version = 3
    private static let maximumPayloadLength = 16_384

    private struct Payload: Codable, Equatable {
        let version: Int
        let preset: SavedTestPreset
    }
    private struct SourcePayload: Codable {
        let version: Int
        let selectionData: Data
    }
    private struct Header: Decodable {
        let version: Int
        let hasPreset: Bool
        let hasSource: Bool
        private enum CodingKeys: String, CodingKey { case version, preset, selectionData }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            hasPreset = values.contains(.preset)
            hasSource = values.contains(.selectionData)
        }
    }

    static func link(for preset: SavedTestPreset) throws -> String {
        let hasSource = PracticeThresholdSource.isPresent(in: preset)
        if hasSource {
            // Validate both carriers before local fields are intentionally removed.
            _ = try LocalPresetCodec.encode(preset)
        }
        let sharedPreset = testConfigurationOnly(preset)
        guard isValid(sharedPreset) else { throw TestConfigurationShareError.invalidConfiguration }
        let data: Data
        if hasSource {
            let encoder = JSONEncoder()
            encoder.userInfo[PracticeThresholdSource.codingCapability] = true
            let selection = try encoder.encode(sharedPreset)
            guard try decodeSourceSelection(selection) == sharedPreset else { throw TestConfigurationShareError.invalidConfiguration }
            data = try JSONEncoder().encode(SourcePayload(version: version, selectionData: selection))
        } else {
            data = try JSONEncoder().encode(Payload(version: 2, preset: sharedPreset))
        }
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard token.count <= maximumPayloadLength else { throw TestConfigurationShareError.invalidConfiguration }
        return "\(scheme)://\(host)?preset=\(token)"
    }

    static func preset(from link: String) throws -> SavedTestPreset {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == scheme,
              components.host == host,
              let token = components.queryItems?.first(where: { $0.name == "preset" })?.value,
              !token.isEmpty,
              token.count <= maximumPayloadLength
        else { throw TestConfigurationShareError.invalidLink }

        var base64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw TestConfigurationShareError.invalidPayload }
        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: data)
        } catch {
            throw TestConfigurationShareError.invalidPayload
        }
        guard (1...version).contains(header.version) else { throw TestConfigurationShareError.unsupportedVersion(header.version) }
        let decoded: SavedTestPreset
        do {
            if header.version == 3 {
                guard header.hasSource, !header.hasPreset else { throw TestConfigurationShareError.invalidPayload }
                let payload = try JSONDecoder().decode(SourcePayload.self, from: data)
                decoded = try decodeSourceSelection(payload.selectionData)
            } else {
                guard header.hasPreset, !header.hasSource else { throw TestConfigurationShareError.invalidPayload }
                decoded = try JSONDecoder().decode(Payload.self, from: data).preset
            }
        } catch { throw TestConfigurationShareError.invalidPayload }
        let sharedPreset = testConfigurationOnly(decoded)
        guard isValid(sharedPreset) else { throw TestConfigurationShareError.invalidConfiguration }
        return sharedPreset
    }

    private static func decodeSourceSelection(_ data: Data) throws -> SavedTestPreset {
        let decoder = JSONDecoder()
        decoder.userInfo[PracticeThresholdSource.codingCapability] = true
        let preset = try decoder.decode(SavedTestPreset.self, from: data)
        guard preset.configuration.rules.thresholdSource != nil,
              preset.settingsSnapshot == nil, preset.activeResultTags == nil, preset.settingGroups == nil,
              isValid(preset) else { throw TestConfigurationShareError.invalidConfiguration }
        _ = try LocalPresetCodec.encode(preset)
        return preset
    }

    /// A `typebar://test` URL is intentionally portable test selection only.
    /// Preset scope, tags and global settings remain local to the originating
    /// Mac even when a caller hands this API a saved full or partial preset.
    private static func testConfigurationOnly(_ preset: SavedTestPreset) -> SavedTestPreset {
        .init(
            configuration: preset.configuration, quoteID: preset.quoteID, customText: preset.customText)
    }

    private static func isValid(_ preset: SavedTestPreset) -> Bool {
        let config = preset.configuration
        switch config.mode {
        case .time:
            guard let duration = config.duration, isValidDuration(duration), config.wordLimit == nil else { return false }
        case .words:
            guard let wordLimit = config.wordLimit, isValidWordLimit(wordLimit), config.duration == nil else { return false }
        case .custom:
            guard let text = preset.customText, CustomTextPolicy.isValid(text, configuration: config) else { return false }
            switch config.customTextCompletion {
            case .finish:
                guard config.duration == nil, config.wordLimit == nil else { return false }
            case .time:
                guard let duration = config.duration, isValidDuration(duration), config.wordLimit == nil else { return false }
            case .words:
                guard let wordLimit = config.wordLimit, isValidWordLimit(wordLimit), config.duration == nil else { return false }
            case .sections:
                guard let sectionLimit = config.customTextSectionLimit,
                      (0...OfficialTestLimitInput.maximumValue).contains(sectionLimit),
                      config.duration == nil, config.wordLimit == nil
                else { return false }
            }
        case .quote, .zen:
            guard config.duration == nil, config.wordLimit == nil else { return false }
        }
        return true
    }

    private static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite
            && duration >= 0
            && duration.rounded(.towardZero) == duration
            && duration <= Double(OfficialTestLimitInput.maximumValue)
    }

    private static func isValidWordLimit(_ wordLimit: Int) -> Bool {
        (0...OfficialTestLimitInput.maximumValue).contains(wordLimit)
    }
}

struct TestConfigurationShareView: View {
  @Environment(\.dismiss) private var dismiss
  let currentPreset: SavedTestPreset
  let legacyCustomTextFallback: LegacyTestSettingsLinkImporter.CustomTextFallback?
  let challengeLibrary: [TypebarChallenge]
  let notices: LocalNoticeCenter
  let onLoadChallenge: (TypebarChallenge) -> TestConfigurationApplyOutcome
  let onApply: (SavedTestPreset) -> SavedTestPreset?
    @State private var pastedLink = ""
    @State private var status: String?

    private var currentLink: String? { try? TestConfigurationShare.link(for: currentPreset) }

  init(
    currentPreset: SavedTestPreset,
    legacyCustomTextFallback: LegacyTestSettingsLinkImporter.CustomTextFallback? = nil,
    challengeLibrary: [TypebarChallenge] = [],
    notices: LocalNoticeCenter,
    onLoadChallenge: @escaping (TypebarChallenge) -> TestConfigurationApplyOutcome = { _ in .rejected },
    onApply: @escaping (SavedTestPreset) -> SavedTestPreset?
  ) {
    self.currentPreset = currentPreset
    self.legacyCustomTextFallback = legacyCustomTextFallback
    self.challengeLibrary = challengeLibrary
    self.notices = notices
    self.onLoadChallenge = onLoadChallenge
    self.onApply = onApply
  }

    var body: some View {
        NavigationStack {
            Form {
                Section("分享当前测试") {
                    Text("链接仅包含测试配置、所选引语 ID 或自定义文本；不会包含账户、成绩或本机设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentLink ?? "当前配置无法分享")
                        .font(.caption.monospaced())
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Button("复制测试链接") { copyCurrentLink() }
                        .disabled(currentLink == nil)
                }

                Section("导入测试链接") {
                    Text("支持自有 typebar://test、网页 testSettings，以及已映射的网页 challenge 链接。网页链接只在本机解码，不会访问其中的主机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("粘贴测试设置链接", text: $pastedLink, axis: .vertical)
                        .lineLimit(2...4)
                    Button("应用导入的测试") { applyPastedLink() }
                        .disabled(pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let status {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("分享测试配置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            }
        }
        .frame(width: 520, height: 380)
    }

    private func copyCurrentLink() {
        guard let currentLink else { return }
        status = TestConfigurationShareActions.copy(currentLink, notices: notices) { value in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(value, forType: .string)
        }
    }

    private func applyPastedLink() {
        let result = TestConfigurationShareActions.apply(pastedLink, current: currentPreset,
            customTextFallback: legacyCustomTextFallback, challenges: challengeLibrary,
            notices: notices, applyPreset: onApply, loadChallenge: onLoadChallenge)
        status = result.status
        if result.shouldDismiss { dismiss() }
    }
}
