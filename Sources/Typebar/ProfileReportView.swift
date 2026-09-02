import SwiftUI

struct ProfileReportView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: RemotePublicProfile
    let account: AccountSession

    @State private var reason: RemoteProfileReportReason = .misleadingProfile
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("举报公开资料")
                    .font(.title2.weight(.semibold))
                Text(profile.displayName)
                    .font(.headline.monospaced())
                    .foregroundStyle(.secondary)
            }

            Picker("问题类别", selection: $reason) {
                ForEach(RemoteProfileReportReason.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("补充说明（可选）")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $note)
                    .font(.body)
                    .frame(minHeight: 88)
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("说明你看到的具体问题")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Text("仅发送给 Typebar 服务的审核队列；不会通知该用户，也不会自动处罚。")
                    Spacer()
                    Text("\(note.count)/400")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let message {
                if message == "举报已提交，等待审核。" {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("提交举报", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || note.count > 400)
            }
        }
        .padding(28)
        .frame(width: 430)
    }

    private func submit() {
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            do {
                _ = try await account.reportProfile(profile.id, reason: reason, note: note)
                message = "举报已提交，等待审核。"
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
