import Foundation
import SwiftUI

enum TestConfigurationShareError: Error, Equatable, LocalizedError {
    case invalidLink
    case invalidPayload
    case unsupportedVersion(Int)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidLink: "这不是有效的 Typebar 测试链接。"
        case .invalidPayload: "测试链接的数据无法读取。"
        case .unsupportedVersion: "此测试链接版本暂不受支持。"
        case .invalidConfiguration: "测试链接包含不支持的配置范围。"
        }
    }
}

enum TestConfigurationShare {
    private static let scheme = "typebar"
    private static let host = "test"
    private static let version = 1
    private static let maximumPayloadLength = 16_384

    private struct Payload: Codable, Equatable {
        let version: Int
        let preset: SavedTestPreset
    }

    static func link(for preset: SavedTestPreset) throws -> String {
        guard isValid(preset) else { throw TestConfigurationShareError.invalidConfiguration }
        let data = try JSONEncoder().encode(Payload(version: version, preset: preset))
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
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw TestConfigurationShareError.invalidPayload
        }
        guard payload.version == version else { throw TestConfigurationShareError.unsupportedVersion(payload.version) }
        guard isValid(payload.preset) else { throw TestConfigurationShareError.invalidConfiguration }
        return payload.preset
    }

    private static func isValid(_ preset: SavedTestPreset) -> Bool {
        let config = preset.configuration
        switch config.mode {
        case .time:
            guard let duration = config.duration, (5...3600).contains(duration), config.wordLimit == nil else { return false }
        case .words:
            guard let wordLimit = config.wordLimit, (1...1000).contains(wordLimit), config.duration == nil else { return false }
        case .custom:
            guard let text = preset.customText, CustomTextPolicy.isValid(text) else { return false }
            switch config.customTextCompletion {
            case .finish:
                guard config.duration == nil, config.wordLimit == nil else { return false }
            case .time:
                guard let duration = config.duration, (5...3600).contains(duration), config.wordLimit == nil else { return false }
            case .words:
                guard let wordLimit = config.wordLimit, (1...1000).contains(wordLimit), config.duration == nil else { return false }
            case .sections:
                guard let sectionLimit = config.customTextSectionLimit,
                      (1...CustomTextPolicy.sections(in: text).count).contains(sectionLimit),
                      config.duration == nil, config.wordLimit == nil
                else { return false }
            }
        case .quote, .zen:
            guard config.duration == nil, config.wordLimit == nil else { return false }
        }
        return true
    }
}

struct TestConfigurationShareView: View {
    @Environment(\.dismiss) private var dismiss
    let currentPreset: SavedTestPreset
    let onApply: (SavedTestPreset) -> Void
    @State private var pastedLink = ""
    @State private var status: String?

    private var currentLink: String? { try? TestConfigurationShare.link(for: currentPreset) }

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
                    TextField("粘贴 typebar://test 链接", text: $pastedLink, axis: .vertical)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentLink, forType: .string)
        status = "测试链接已复制。"
    }

    private func applyPastedLink() {
        do {
            onApply(try TestConfigurationShare.preset(from: pastedLink))
            dismiss()
        } catch {
            status = (error as? LocalizedError)?.errorDescription ?? "无法导入该测试链接。"
        }
    }
}
