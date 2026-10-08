import Foundation
import XCTest
@testable import Typebar

@MainActor final class LocalNoticeTests: XCTestCase {
  func testHistoryIsLastTwentyFiveOldestFirstButLiveNoticesAreNewestFirst() {
    let center = LocalNoticeCenter()
    for index in 0..<30 { center.post("Owned \(index)", options: .init(durationMilliseconds: 0)) }
    XCTAssertEqual(center.history.map(\.message), (5..<30).map { "Owned \($0)" })
    XCTAssertEqual(center.active.map(\.entry.message), (0..<30).reversed().map { "Owned \($0)" })
    XCTAssertEqual(Set(center.active.map(\.id)).count, 30)
    center.remove(center.active[0].id); center.clearAll()
    XCTAssertEqual(center.history.count, 25); XCTAssertTrue(center.active.isEmpty)
  }

  func testLevelsDefaultsCustomEmptyTitleAndLiteralHTMLArePreserved() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    for level in LocalNoticeLevel.allCases { center.post("Owned", level: level) }
    XCTAssertEqual(center.active.map(\.durationMilliseconds), [0, 3000, 3000])
    XCTAssertEqual(center.history.map(\.title), ["提示", "成功", "错误"])
    center.post("<b>Owned & text</b>", options: .init(durationMilliseconds: -1, title: "", systemImage: "gift", containsHTML: true))
    XCTAssertEqual(center.history.last?.title, ""); XCTAssertEqual(center.active.first?.systemImage, "gift")
    XCTAssertEqual(center.history.last?.message, "<b>Owned & text</b>"); XCTAssertTrue(center.history.last?.containsHTML == true)
  }

  func testFocusScreenshotAndStickyCountDoNotRemoveHistoryOrHiddenTimers() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    center.post("Normal", options: .init(durationMilliseconds: 0))
    let important = center.post("Important", options: .init(important: true, durationMilliseconds: 0))
    center.post("Negative", options: .init(durationMilliseconds: -1))
    XCTAssertEqual(center.visible(focused: true).map(\.id), [important])
    XCTAssertTrue(center.visible(focused: false, screenshotting: true).isEmpty)
    XCTAssertEqual(center.stickyCount(focused: false), 2); XCTAssertEqual(center.stickyCount(focused: true), 1)
    XCTAssertEqual(center.history.count, 3)
  }

  func testClickAndClearCallbacksAreOnceOnlyAndReentrantPostsSurviveClear() {
    let center = LocalNoticeCenter(); var reasons: [String] = []
    let first = center.post("First", options: .init(durationMilliseconds: 0)) { reasons.append("First:\($0.rawValue)") }
    center.remove(first); center.remove(first)
    center.post("Second", options: .init(durationMilliseconds: 0)) { reasons.append("Second:\($0.rawValue)") }
    center.post("Third", options: .init(durationMilliseconds: 0)) {
      reasons.append("Third:\($0.rawValue)")
      center.post("Reentrant", options: .init(durationMilliseconds: 0))
    }
    center.clearAll()
    XCTAssertEqual(reasons, ["First:click", "Third:clear", "Second:clear"])
    XCTAssertEqual(center.active.map(\.entry.message), ["Reentrant"]); XCTAssertEqual(center.history.count, 4)
    center.clearAll()
  }

  func testTimerUsesExitAllowanceAndLateCancelledTimerCannotDismissAnotherNotice() async {
    var pending: CheckedContinuation<Void, Error>?, waits: [Int] = [], reasons: [LocalNoticeDismissReason] = []
    let center = LocalNoticeCenter { delay in
      waits.append(delay)
      try await withCheckedThrowingContinuation { pending = $0 }
    }
    let first = center.post("First", options: .init(durationMilliseconds: 10)) { reasons.append($0) }
    for _ in 0..<20 where pending == nil { await Task.yield() }
    XCTAssertEqual(waits, [260]); XCTAssertNotNil(pending)
    center.remove(first)
    let newer = center.post("New", options: .init(durationMilliseconds: 0))
    pending?.resume(); pending = nil
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(reasons, [.click]); XCTAssertEqual(center.active.map(\.id), [newer])
    center.clearAll()
  }

  func testActualTimerTimeoutPreservesHistoryAndScopeRetirementSkipsOldCallbacks() async {
    var pending: CheckedContinuation<Void, Error>?, reasons: [LocalNoticeDismissReason] = []
    let center = LocalNoticeCenter { _ in try await withCheckedThrowingContinuation { pending = $0 } }
    center.post("Expiring", options: .init(durationMilliseconds: 1)) { reasons.append($0) }
    for _ in 0..<20 where pending == nil { await Task.yield() }
    XCTAssertNotNil(pending); pending?.resume(); pending = nil
    for _ in 0..<20 where !center.active.isEmpty { await Task.yield() }
    XCTAssertTrue(center.active.isEmpty); XCTAssertEqual(center.history.count, 1); XCTAssertEqual(reasons, [.timeout])
    center.post("Retired", options: .init(durationMilliseconds: 1)) { reasons.append($0) }
    for _ in 0..<20 where pending == nil { await Task.yield() }
    center.clearForAccountChange(); pending?.resume(); pending = nil
    for _ in 0..<20 { await Task.yield() }
    XCTAssertTrue(center.history.isEmpty); XCTAssertTrue(center.active.isEmpty); XCTAssertEqual(reasons, [.timeout])
  }

  func testTimerDoesNotRetainCenterAndMaximumDelayCannotOverflow() async {
    var pending: CheckedContinuation<Void, Error>?, waits: [Int] = [], callbacks = 0
    var center: LocalNoticeCenter? = LocalNoticeCenter { delay in
      waits.append(delay); try await withCheckedThrowingContinuation { pending = $0 }
    }
    weak var weakCenter = center
    center?.post("Owned maximum", options: .init(durationMilliseconds: Int.max)) { _ in callbacks += 1 }
    for _ in 0..<20 where pending == nil { await Task.yield() }
    XCTAssertEqual(waits, [Int.max]); XCTAssertNotNil(pending)
    center = nil; XCTAssertNil(weakCenter)
    pending?.resume(); pending = nil
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(callbacks, 0)
  }

  func testResponseCompositionAndDetailsCopyKeepStructuredDataWithoutCapturingObjects() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    center.post("Owned failure", level: .error, options: .init(details: .string("Owned diagnostic"),
      response: .init(status: 422, message: "Owned response", validationErrors: .array([.string("field")])), errorMessage: "Owned error"))
    let entry = try XCTUnwrap(center.history.last)
    XCTAssertEqual(entry.message, "Owned failure: Owned response: Owned error")
    var copied: String?
    XCTAssertTrue(LocalNoticeClipboard.copyDetails(entry) { copied = $0; return true })
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(copied).utf8)) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["title", "message", "details"])
    let details = try XCTUnwrap(object["details"] as? [String: Any])
    XCTAssertEqual(details["status"] as? Int, 422); XCTAssertEqual(details["additionalDetails"] as? String, "Owned diagnostic")
    XCTAssertEqual(details["validationErrors"] as? [String], ["field"])
    XCTAssertFalse(LocalNoticeClipboard.copyDetails(entry) { _ in false })
    center.post("No details", options: .init(durationMilliseconds: 0))
    XCTAssertFalse(LocalNoticeClipboard.copyDetails(try XCTUnwrap(center.history.last)) { _ in XCTFail("No copy action without details"); return true })
  }

  func testJSONKindsNullOmissionAndNonFiniteDetailsFailureAreExplicit() throws {
    let value = LocalNoticeJSON.object(["null": .null, "bool": .bool(true), "number": .number(1.5), "array": .array([.string("Owned")])])
    XCTAssertEqual(try JSONDecoder().decode(LocalNoticeJSON.self, from: JSONEncoder().encode(value)), value)
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    center.post("Owned", options: .init(durationMilliseconds: 0, response: .init(status: 500, message: "Owned", validationErrors: .string("must be omitted"))))
    XCTAssertEqual(center.history.last?.details, .object(["status": .number(500)]))
    center.post("Explicit null", options: .init(durationMilliseconds: 0, details: .null))
    XCTAssertTrue(LocalNoticeClipboard.copyDetails(try XCTUnwrap(center.history.last)) { $0.contains("null") })
    center.post("Invalid diagnostic", options: .init(durationMilliseconds: 0, details: .number(.infinity)))
    XCTAssertFalse(LocalNoticeClipboard.copyDetails(try XCTUnwrap(center.history.last)) { _ in XCTFail("Encoding failure must not write"); return true })
  }

  func testProductionClipboardHelperUsesActualWriteOutcomeAndDoesNotStoreCopiedContent() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    var writes: [String] = []
    XCTAssertEqual(LocalNoticeClipboard.copyText("Owned private input", center: center, success: "Copied") { writes.append($0); return true }, "Copied")
    XCTAssertEqual(center.history.last?.level, .success)
    _ = LocalNoticeClipboard.copyText("Owned private input", center: center, success: "Copied") { writes.append($0); return false }
    XCTAssertEqual(center.history.last?.level, .error); XCTAssertEqual(writes.count, 2)
    XCTAssertTrue(center.history.allSatisfy { !$0.message.contains("Owned private input") && $0.details == nil })
  }

  func testAccountAndServerChangesRetireHistoryButSameUserProfileRefreshDoesNot() throws {
    let suite = "TypebarTests.local-notices.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults), id = UUID()
    account.currentUser = .init(id: id, email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    account.localNotices.post("Owned", options: .init(durationMilliseconds: 0))
    account.currentUser = .init(id: id, email: "owned@example.invalid", displayName: "Owned", totalExperience: 5)
    XCTAssertEqual(account.localNotices.history.count, 1)
    account.currentUser = nil; XCTAssertTrue(account.localNotices.history.isEmpty)
    account.localNotices.post("Anonymous", options: .init(durationMilliseconds: 0))
    _ = account.updateEndpoint("https://owned.invalid/base"); XCTAssertTrue(account.localNotices.history.isEmpty)
  }

  func testNativeStateAgainstCompletePinnedNotificationModuleTransitions() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned reference") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-local-notices.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let actions = try XCTUnwrap(document["actions"] as? [[String: Any]]), snapshots = try XCTUnwrap(document["snapshots"] as? [[String: Any]])
    XCTAssertEqual(actions.count, 43); XCTAssertEqual(actions.count, snapshots.count)
    var delays: [Int] = [], calls: [String] = [], ids: [String: UUID] = [:]
    let center = LocalNoticeCenter { delay in delays.append(delay); try await Task.sleep(for: .seconds(3600)) }
    defer { center.clearAll() }
    func json(_ value: Any) throws -> LocalNoticeJSON {
      try JSONDecoder().decode(LocalNoticeJSON.self, from: JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
    }
    func entry(_ value: LocalNoticeEntry) throws -> [String: Any] {
      var result: [String: Any] = ["title": value.title, "message": value.message, "level": value.level.rawValue, "html": value.containsHTML]
      if let details = value.details { result["details"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(details), options: .fragmentsAllowed) }
      return result
    }
    for (index, action) in actions.enumerated() {
      let message = action["message"] as? String ?? ""
      switch action["op"] as? String {
      case "post":
        let options = action["options"] as? [String: Any] ?? [:], response = options["response"] as? [String: Any]
        let body = response?["body"] as? [String: Any] ?? [:]
        let value = LocalNoticeOptions(important: options["important"] as? Bool ?? false,
          durationMilliseconds: options["durationMs"] as? Int, title: options["customTitle"] as? String,
          systemImage: options["customIcon"] as? String, details: try options["details"].map(json),
          response: try response.map { .init(status: $0["status"] as! Int, message: body["message"] as! String,
            validationErrors: try body["validationErrors"].map(json)) },
          errorMessage: options["error"] as? String, containsHTML: options["useInnerHtml"] as? Bool ?? false)
        ids[message] = center.post(message, level: try XCTUnwrap(LocalNoticeLevel(rawValue: action["level"] as! String)), options: value) {
          calls.append("\(message):\($0.rawValue)")
        }
      case "remove": center.remove(try XCTUnwrap(ids[message]))
      case "clear": center.clearAll()
      default: XCTFail("Unknown owned action")
      }
      for _ in 0..<20 { await Task.yield() }
      var expected = snapshots[index]
      expected["history"] = (expected["history"] as! [[String: Any]]).map { row in
        var row = row
        if let title = row["title"] as? String { row["title"] = ["Notice": "提示", "Success": "成功", "Error": "错误"][title] ?? title }
        return row
      }
      let actual: [String: Any] = ["active": center.active.map { ["message": $0.entry.message, "level": $0.entry.level.rawValue,
        "important": $0.important, "duration": $0.durationMilliseconds, "html": $0.entry.containsHTML] },
        "history": try center.history.map(entry), "calls": calls, "delays": delays]
      XCTAssertEqual(actual as NSDictionary, expected as NSDictionary, "Owned transition \(index): \(action)")
    }
  }
}
