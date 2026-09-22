import SwiftUI

/// A deliberately compact native decision sheet for a result that already
/// lives safely in local history. It does not enable background publication or
/// remove the local record; only the explicit upload control crosses the
/// network boundary.
@MainActor
struct SignedOutResultClaimView: View {
  let result: CompletedTestResult
  let onKeepLocal: () -> Void
  let onUpload: () async throws -> Void

  @State private var isUploading = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "arrow.up.circle")
          .font(.title2)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text("上传刚才的离线成绩？")
            .font(.title3.weight(.semibold))
          Text("这局成绩已保存在这台 Mac。只有你确认后，才会发送到当前已登录的成绩服务。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Grid(alignment: .leading, horizontalSpacing: 34, verticalSpacing: 10) {
        GridRow {
          metric("速度", "\(result.wpm) WPM")
          metric("准确率", "\(result.accuracy)%")
        }
        GridRow {
          metric("原始速度", "\(result.rawWpm) WPM")
          metric("错误", "\(result.errorCount) 个")
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      Label("上传不会开启自动发布，也不会删除这台 Mac 上的本机成绩。", systemImage: "lock")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Button("保留在本机", action: onKeepLocal)
          .disabled(isUploading)
        Spacer()
        Button {
          upload()
        } label: {
          if isUploading {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text("正在上传…")
            }
          } else {
            Text("上传这局成绩")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isUploading)
      }
    }
    .padding(24)
    .frame(width: 460)
  }

  private func metric(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline.monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func upload() {
    Task {
      isUploading = true
      errorMessage = nil
      defer { isUploading = false }
      do {
        try await onUpload()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
