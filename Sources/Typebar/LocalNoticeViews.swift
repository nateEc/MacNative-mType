import AppKit
import SwiftUI

private extension LocalNoticeLevel {
  var color: Color { switch self { case .notice: .secondary; case .success: .green; case .error: .red } }
}

struct LocalNoticeStack: View {
  let center: LocalNoticeCenter
  let focused: Bool
  var screenshotting = false
  var body: some View {
    VStack(alignment: .trailing, spacing: 8) {
      if !screenshotting, center.stickyCount(focused: focused) > 1 {
        Button("关闭全部临时通知") { center.clearAll() }.font(.caption)
      }
      ForEach(center.visible(focused: focused, screenshotting: screenshotting)) { notice in
        Button { center.remove(notice.id) } label: {
          VStack(alignment: .leading, spacing: 6) {
            Label(notice.entry.title, systemImage: notice.systemImage)
              .font(.caption.weight(.semibold)).foregroundStyle(notice.entry.level.color)
            Text(verbatim: notice.entry.message).font(.callout).fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(14)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
          .overlay(alignment: .leading) { Capsule().fill(notice.entry.level.color).frame(width: 3).padding(.vertical, 10) }
        }.buttonStyle(.plain).help("关闭这条临时通知；历史仍保留")
          .accessibilityLabel("\(notice.entry.title)：\(notice.entry.message)。关闭通知。")
      }
    }.frame(width: 340)
  }
}

struct LocalNoticeHistoryView: View {
  let center: LocalNoticeCenter
  @Environment(\.dismiss) private var dismiss
  @State private var copyMessage: String?
  var body: some View {
    NavigationStack {
      ScrollView {
        LocalNoticeHistoryContent(entries: Array(center.history.reversed()), copy: { entry in
          let copied = LocalNoticeClipboard.copyDetails(entry) { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
          }
          copyMessage = copied ? "通知详情已复制。" : "无法复制通知详情，请重试。"
        })
      }
      .safeAreaInset(edge: .bottom) {
        if let copyMessage { Text(copyMessage).font(.caption).textSelection(.enabled).padding() }
      }
      .navigationTitle("会话通知")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }.frame(minWidth: 420, idealWidth: 520, minHeight: 320)
  }
}

/// Account-free production content. Opening history does not fetch mail or mark anything read.
struct LocalNoticeHistoryContent: View {
  let entries: [LocalNoticeEntry]
  let copy: (LocalNoticeEntry) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("本次会话最近 25 条，最新在前。关闭临时通知不会删除历史；切换账户或服务会清空。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if entries.isEmpty {
        ContentUnavailableView("没有会话通知", systemImage: "bell", description: Text("复制结果或领取奖励后的提示会显示在这里，不需要登录。"))
      } else {
        ForEach(entries) { entry in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.level.systemImage).foregroundStyle(entry.level.color)
            VStack(alignment: .leading, spacing: 6) {
              Text(verbatim: entry.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              Text(verbatim: entry.message).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
              if entry.containsHTML { Text("包含网页格式，按原始文本显示。").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if entry.details != nil {
              Button("复制详情", systemImage: "doc.on.doc") { copy(entry) }
                .labelStyle(.iconOnly).help("复制 \(entry.title) 的 JSON 详情")
                .accessibilityLabel("复制 \(entry.title) 的通知详情")
            }
          }
          Divider()
        }
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
  }
}
