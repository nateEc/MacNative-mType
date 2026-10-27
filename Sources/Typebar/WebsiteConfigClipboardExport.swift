import AppKit
import Observation

@MainActor @Observable final class WebsiteConfigClipboardExport {
  struct ManualCopy: Identifiable {
    let id = UUID()
    let json: String
  }
  var manualCopy: ManualCopy?
  private(set) var message: String?
  private(set) var noticeID = UUID()
  private(set) var noticeDurationMilliseconds: Int?

  func copy(read: @escaping @MainActor () throws -> String,
    write: @MainActor (String) -> Bool = WebsiteConfigClipboardExport.write,
    schedule: @MainActor (Int, @escaping @MainActor () -> Void) -> Void = WebsiteConfigClipboardExport.schedule) {
    do {
      let json = try read()
      noticeID = UUID()
      if write(json) {
        message = "设置 JSON 已复制。"
        noticeDurationMilliseconds = nil
      } else {
        message = "无法写入剪贴板，请手动复制设置 JSON。"
        noticeDurationMilliseconds = 5000
        schedule(250) { [weak self] in
          guard let self else { return }
          do { self.manualCopy = .init(json: try read()) }
          catch { self.message = "无法生成设置 JSON：\(error.localizedDescription)" }
        }
      }
    } catch {
      message = "无法生成设置 JSON：\(error.localizedDescription)"
    }
  }

  func clearNotice(_ id: UUID) {
    if noticeID == id { message = nil }
  }

  private static func write(_ json: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(json, forType: .string)
  }
  private static func schedule(_ milliseconds: Int, action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(milliseconds))
      action()
    }
  }
}
