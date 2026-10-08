import Foundation
import Observation

enum LocalNoticeLevel: String, Codable, CaseIterable {
  case notice, success, error
  var title: String { switch self { case .notice: "提示"; case .success: "成功"; case .error: "错误" } }
  var systemImage: String { switch self { case .notice: "info.circle"; case .success: "checkmark.circle"; case .error: "exclamationmark.circle" } }
}

/// Structured, explicitly supplied diagnostics only; never captures a response or Error object.
indirect enum LocalNoticeJSON: Codable, Equatable {
  case null, bool(Bool), number(Double), string(String), array([Self]), object([String: Self])
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() { self = .null }
    else if let result = try? value.decode(Bool.self) { self = .bool(result) }
    else if let result = try? value.decode(Double.self) { self = .number(result) }
    else if let result = try? value.decode(String.self) { self = .string(result) }
    else if let result = try? value.decode([Self].self) { self = .array(result) }
    else { self = .object(try value.decode([String: Self].self)) }
  }
  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .null: try value.encodeNil()
    case .bool(let result): try value.encode(result)
    case .number(let result): try value.encode(result)
    case .string(let result): try value.encode(result)
    case .array(let result): try value.encode(result)
    case .object(let result): try value.encode(result)
    }
  }
}

struct LocalNoticeResponse {
  let status: Int
  let message: String
  var validationErrors: LocalNoticeJSON? = nil
}

struct LocalNoticeOptions {
  var important = false
  var durationMilliseconds: Int? = nil
  var title: String? = nil
  var systemImage: String? = nil
  var details: LocalNoticeJSON? = nil
  var response: LocalNoticeResponse? = nil
  var errorMessage: String? = nil
  var containsHTML = false
}

struct LocalNoticeEntry: Identifiable, Equatable {
  let id: UUID
  let title: String
  let message: String
  let level: LocalNoticeLevel
  let details: LocalNoticeJSON?
  let containsHTML: Bool
  func detailsText() throws -> String {
    struct Payload: Encodable { let title: String; let message: String; let details: LocalNoticeJSON? }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(Payload(title: title, message: message, details: details)), as: UTF8.self)
  }
}

struct LocalNotice: Identifiable, Equatable {
  let entry: LocalNoticeEntry
  let important: Bool
  let durationMilliseconds: Int
  let systemImage: String
  var id: UUID { entry.id }
}

enum LocalNoticeDismissReason: String { case click, timeout, clear }

/// Shared by this app's windows, but only for the current account/server lifetime.
/// History and timers are memory-only, separate from social events and reward mail.
@MainActor @Observable final class LocalNoticeCenter {
  typealias Sleep = @MainActor (Int) async throws -> Void
  private(set) var active: [LocalNotice] = []
  private(set) var history: [LocalNoticeEntry] = []
  @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var dismissals: [UUID: (LocalNoticeDismissReason) -> Void] = [:]
  @ObservationIgnored private let sleep: Sleep
  init(sleep: @escaping Sleep = { try await Task.sleep(for: .milliseconds($0)) }) { self.sleep = sleep }
  deinit { for task in timers.values { task.cancel() } }

  @discardableResult func post(_ message: String, level: LocalNoticeLevel = .notice,
    options: LocalNoticeOptions = .init(), onDismiss: ((LocalNoticeDismissReason) -> Void)? = nil) -> UUID {
    var message = message, details = options.details
    if let response = options.response {
      var fields: [String: LocalNoticeJSON] = ["status": .number(Double(response.status))]
      fields["additionalDetails"] = details
      if response.status == 422 { fields["validationErrors"] = response.validationErrors }
      details = .object(fields); message += ": " + response.message
    }
    if let error = options.errorMessage { message += ": " + (error.isEmpty ? "未知错误" : error) }
    let id = UUID(), duration = options.durationMilliseconds ?? (level == .error ? 0 : 3000)
    let entry = LocalNoticeEntry(id: id, title: options.title ?? level.title, message: message,
      level: level, details: details, containsHTML: options.containsHTML)
    history.append(entry)
    if history.count > 25 { history.removeFirst(history.count - 25) }
    active.insert(.init(entry: entry, important: options.important, durationMilliseconds: duration,
      systemImage: options.systemImage ?? level.systemImage), at: 0)
    dismissals[id] = onDismiss
    if duration > 0 {
      let wait = min(duration, Int.max - 250) + 250, sleep = sleep
      timers[id] = Task { @MainActor [weak self] in
        do { try Task.checkCancellation(); try await sleep(wait); try Task.checkCancellation() }
        catch { return }
        self?.remove(id, reason: .timeout)
      }
    }
    return id
  }
  func visible(focused: Bool, screenshotting: Bool = false) -> [LocalNotice] {
    screenshotting ? [] : active.filter { !focused || $0.important }
  }
  func stickyCount(focused: Bool) -> Int {
    visible(focused: focused).filter { $0.durationMilliseconds == 0 }.count
  }
  func remove(_ id: UUID, reason: LocalNoticeDismissReason = .click) {
    guard let index = active.firstIndex(where: { $0.id == id }) else { return }
    active.remove(at: index); timers.removeValue(forKey: id)?.cancel()
    let callback = dismissals.removeValue(forKey: id)
    callback?(reason)
  }
  func clearAll() {
    let callbacks = active.compactMap { dismissals[$0.id] }
    cancelTimers(); active = []; dismissals = [:]
    // Retire the old batch before invoking callbacks; reentrant notices survive.
    for callback in callbacks { callback(.clear) }
  }
  func clearForAccountChange() {
    cancelTimers(); active = []; history = []; dismissals = [:]
    // Do not run callbacks belonging to the retired account/server.
  }
  private func cancelTimers() { for task in timers.values { task.cancel() }; timers = [:] }
}

enum LocalNoticeClipboard {
  @MainActor static func copyText(_ text: String, center: LocalNoticeCenter, success: String,
    write: (String) -> Bool) -> String {
    let ok = write(text), message = ok ? success : "无法写入剪贴板，请重试。"
    center.post(message, level: ok ? .success : .error)
    return message
  }
  static func copyDetails(_ entry: LocalNoticeEntry, write: (String) -> Bool) -> Bool {
    guard entry.details != nil, let text = try? entry.detailsText() else { return false }
    return write(text)
  }
}
