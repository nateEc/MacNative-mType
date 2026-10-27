import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class WebsiteTestSettingsShareController {
  var selected = Set<WebsiteTestSettingsShare.Field>()
  private(set) var status: String?
  @ObservationIgnored private let read: @MainActor () -> WebsiteTestSettingsShare.Snapshot?
  @ObservationIgnored private let write: @MainActor (String) -> Bool
  @ObservationIgnored private let notices: LocalNoticeCenter
  init(read: @escaping @MainActor () -> WebsiteTestSettingsShare.Snapshot?, notices: LocalNoticeCenter,
    write: @escaping @MainActor (String) -> Bool = { value in
      NSPasteboard.general.clearContents()
      return NSPasteboard.general.setString(value, forType: .string)
    }) {
    self.read = read; self.notices = notices; self.write = write
  }
  var snapshot: WebsiteTestSettingsShare.Snapshot? { read() }
  var mode: String? { snapshot?.runtime["mode"]?.stringUnits.map { String(decoding: $0, as: UTF16.self) } }
  var visibleFields: [WebsiteTestSettingsShare.Field] { WebsiteTestSettingsShare.Field.allCases.filter { $0.isVisible(mode: mode) } }
  var link: String? {
    guard let snapshot else { return nil }
    return try? WebsiteTestSettingsShare.link(snapshot, selected: selected)
  }
  var isLong: Bool { (link?.utf16.count ?? 0) > 2000 }
  var failureMessage: String? {
    guard let snapshot else { return WebsiteTestSettingsShare.Failure.unavailable.errorDescription }
    do { _ = try WebsiteTestSettingsShare.link(snapshot, selected: selected); return nil }
    catch { return (error as? WebsiteTestSettingsShare.Failure)?.errorDescription
      ?? WebsiteTestSettingsShare.Failure.unavailable.errorDescription }
  }
  func isEnabled(_ field: WebsiteTestSettingsShare.Field) -> Bool {
    if snapshot?.unavailableFields.contains(field) == true { return false }
    if field.requiresModeSelection && !selected.contains(.mode) { return false }
    if field == .parameter, mode == "quote", snapshot?.hasUnmappedQuote == true { return false }
    return true
  }
  func copy() {
    do {
      guard let snapshot else { throw WebsiteTestSettingsShare.Failure.unavailable }
      let current = try WebsiteTestSettingsShare.link(snapshot, selected: selected)
      status = TestConfigurationShareActions.copy(current, notices: notices, write: write)
    } catch {
      let message = (error as? WebsiteTestSettingsShare.Failure)?.errorDescription
        ?? WebsiteTestSettingsShare.Failure.unavailable.errorDescription!
      status = message
      notices.post(message)
    }
  }
}

struct WebsiteTestSettingsShareSection: View {
  @Bindable var controller: WebsiteTestSettingsShareController
  var body: some View {
    let link = controller.link
    Section("选择分享项目") {
      Text("仅分享勾选的项目，采用原版八项设置格式。下方完整测试链接可保留 Typebar 自有引语编号。")
        .font(.caption).foregroundStyle(.secondary)
      ForEach(controller.visibleFields, id: \.rawValue) { field in
        Toggle(field.title, isOn: Binding(get: { controller.selected.contains(field) }, set: { enabled in
          if enabled { controller.selected.insert(field) } else { controller.selected.remove(field) }
        }))
        .disabled(!controller.isEnabled(field) && !controller.selected.contains(field))
      }
      if let snapshot = controller.snapshot, !snapshot.unavailableFields.isEmpty {
        let titles = controller.visibleFields.filter(snapshot.unavailableFields.contains).map(\.title)
        if !titles.isEmpty {
          Text("八项格式无法表达：" + titles.joined(separator: "、") + "。完整测试链接可保留原生设置。")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if controller.mode == "quote", controller.snapshot?.hasUnmappedQuote == true {
        Text(WebsiteTestSettingsShare.Failure.unmappedQuote.errorDescription!)
          .font(.caption).foregroundStyle(.secondary)
      }
      WebsiteConfigReadOnlyText(json: link ?? "", accessibilityLabel: "只读测试链接",
        accessibilityIdentifier: "website-test-settings-url")
        .frame(height: 72)
      Button("复制所选项目链接") { controller.copy() }.disabled(link == nil)
      if link == nil, let failure = controller.failureMessage {
        Text(failure).font(.caption).foregroundStyle(.secondary)
      }
      if (link?.utf16.count ?? 0) > 2000 {
        Label("链接超过 2000 字符，部分应用可能无法完整打开。", systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.orange)
      }
      if let status = controller.status { Text(status).font(.caption).foregroundStyle(.secondary) }
    }
  }
}
