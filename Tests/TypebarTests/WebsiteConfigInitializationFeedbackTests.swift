import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigInitializationFeedbackTests: XCTestCase {
  @MainActor private final class Permit { var current = true }
  @MainActor private final class RegionLifetime { var entered = 0; var left = 0 }
  @MainActor private struct TypingProbe: View {
    let lifetime: RegionLifetime
    var body: some View {
      Text("Owned old typing region").onAppear { lifetime.entered += 1 }.onDisappear { lifetime.left += 1 }
    }
  }

  func testExhaustedRegionHidesOldTypingAndCanRestoreItForRetry() {
    let lifetime = RegionLifetime()
    func region(_ message: String?) -> some View {
      WebsiteConfigInitializationRegion(message: message, retry: {}) { TypingProbe(lifetime: lifetime) }
        .frame(width: 600, height: 300)
    }
    let host = NSHostingView(rootView: region("Owned final failure"))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 300),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(lifetime.entered, 0)
    host.rootView = region(nil)
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(lifetime.entered, 1)
    host.rootView = region("Owned next failure")
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(lifetime.left, 1); XCTAssertFalse(window.isVisible)
  }
  @MainActor private final class DiagnosticCounter { var formats = 0 }
  private struct DiagnosticError: LocalizedError {
    let counter: DiagnosticCounter
    var errorDescription: String? { MainActor.assumeIsolated { counter.formats += 1; return "Owned reason" } }
  }

  func testNilReportDoesNotEvaluatePresentationDiagnostics() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-no-feedback-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = PreferenceConfigurationSaveRouter(), owner = UUID(), epoch = UUID()
    router.register(owner: owner, save: { XCTFail("No legacy writes") })
    let coordinator = WebsiteConfigCommitCoordinator(router: router, register: .init(directory: directory),
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"quote"}"#),
      localFont: .absent, localBackground: .absent)
    let counter = DiagnosticCounter()
    var reads = 0
    do {
      _ = try await coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in
        reads += 1; throw DiagnosticError(counter: counter)
      })
      XCTFail("Failure delivered")
    } catch is DiagnosticError {}
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(counter.formats, 0, "No report means no human-description callbacks")
  }

  func testRetiredNoticeGenerationCannotPostIntoANewAccountHistory() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let generation = center.deliveryGeneration
    center.clearForAccountChange()
    XCTAssertNil(center.postGuarded("Old", level: .error, options: .init(), generation: generation, whileCurrent: { true }))
    XCTAssertTrue(center.active.isEmpty); XCTAssertTrue(center.history.isEmpty)
  }

  func testAccountChangeDuringPostingKeepsOnlyNewAccountNotice() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let generation = center.deliveryGeneration
    let once = Permit()
    withObservationTracking { _ = center.history } onChange: {
      MainActor.assumeIsolated {
        guard once.current else { return }; once.current = false
        center.clearForAccountChange()
        center.post("New account", options: .init(durationMilliseconds: 0))
      }
    }
    XCTAssertNil(center.postGuarded("Old", level: .error, options: .init(), generation: generation, whileCurrent: { true }))
    XCTAssertEqual(center.history.map(\.message), ["New account"])
    XCTAssertEqual(center.active.map(\.entry.message), ["New account"])
    XCTAssertFalse(once.current)
  }

  func testRetiredRequestDoesNotEvictHistoryAtTheTwentyFiveEntryBoundary() {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    for index in 0..<25 { center.post("Owned \(index)", options: .init(durationMilliseconds: 0)) }
    let history = center.history, active = center.active, permit = Permit()
    withObservationTracking { _ = center.history } onChange: {
      MainActor.assumeIsolated { permit.current = false }
    }
    XCTAssertNil(center.postGuarded("Retired", level: .error, options: .init(), generation: center.deliveryGeneration,
      whileCurrent: { permit.current }))
    XCTAssertEqual(center.history, history)
    XCTAssertEqual(center.active, active)
  }

  func testDiagnosticsUseOnlyExplicitLiteralReasonsWithBoundedVisibleText() throws {
    let center = LocalNoticeCenter(); defer { center.clearAll() }
    let report = WebsiteConfigInitializationReport(notices: center)
    let text = "<script>Owned</script> " + String(repeating: "自有诊断", count: 400)
    let error = NSError(domain: "Owned", code: 1,
      userInfo: [NSLocalizedDescriptionKey: text, "secret": "must-not-be-captured"])
    report.record(.init(attempt: 1, level: .error, message: "Owned", reason: nil, category: "test"), whileCurrent: { false })
    XCTAssertTrue(center.history.isEmpty)
    report.record(WebsiteConfigInitializationReport.generation(attempt: 1, error: error, quote: nil), whileCurrent: { true })
    let entry = try XCTUnwrap(center.history.first)
    XCTAssertFalse(entry.containsHTML)
    XCTAssertLessThanOrEqual(entry.message.count, 87)
    XCTAssertTrue(entry.message.contains("<script>Owned</script>"))
    let details = try entry.detailsText()
    XCTAssertFalse(details.contains("must-not-be-captured"))
    XCTAssertFalse(details.contains("\"secret\""))
    guard case .object(let fields) = entry.details, case .string(let reason) = fields["reason"] else {
      return XCTFail("Missing explicit reason")
    }
    XCTAssertEqual(fields["attempt"], .number(1))
    XCTAssertLessThanOrEqual(reason.count, 1000)
    XCTAssertNil(report.finalMessage)
  }

  func testCompletePinnedInitFeedbackMatchesNativeSeverityImportanceAndSilentErrors() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Notice: Decodable { let level: String; let important: Bool }
    struct Case: Decodable {
      let outcomes: [String], success: Bool, calls: Int, notifications: [Notice], finalErrors: [String], capturedMessages: [String]
    }
    struct PreflightCase: Decodable {
      let mode: String, groups: [Int], authenticated: Bool, corrected: Bool, calls: Int
      let selectionAtGeneration: [[Int]]
    }
    struct Output: Decodable { let cases: [Case]; let preflightCases: [PreflightCase] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-initial-generation-retries.mjs").path,
      reference, "--json"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    let cases = output.cases
    XCTAssertEqual(output.preflightCases.count, 5)
    for fixture in output.preflightCases {
      let corrected = fixture.mode == "quote" && fixture.groups.contains(-3) && !fixture.authenticated
      XCTAssertEqual(fixture.corrected, corrected)
      XCTAssertEqual(fixture.calls, 3)
      XCTAssertEqual(fixture.selectionAtGeneration, Array(repeating: corrected ? [0,1,2,3] : fixture.groups, count: 3))
    }
    XCTAssertEqual(cases.count, 5)
    for fixture in cases {
      let center = LocalNoticeCenter(); defer { center.clearAll() }
      let report = WebsiteConfigInitializationReport(notices: center)
      for (index, outcome) in fixture.outcomes.enumerated() where outcome != "valid" {
        let error: Error = outcome == "reject"
          ? NSError(domain: "Owned", code: index, userInfo: [NSLocalizedDescriptionKey: "Owned generation rejection"])
          : WebsiteWordGenerationError(message: outcome == "blank" ? "" : "Owned empty generation")
        report.record(WebsiteConfigInitializationReport.generation(attempt: index + 1, error: error, quote: nil), whileCurrent: { true })
      }
      if !fixture.success { report.finish() }
      XCTAssertEqual(fixture.calls, 3)
      XCTAssertEqual(center.history.map { $0.level.rawValue }, fixture.notifications.map(\.level))
      XCTAssertTrue(center.active.allSatisfy(\.important)); XCTAssertTrue(fixture.notifications.allSatisfy(\.important))
      XCTAssertEqual(report.finalMessage == nil, fixture.finalErrors.isEmpty)
      XCTAssertEqual(fixture.capturedMessages.count, fixture.success ? 0 : 1)
      XCTAssertEqual(report.failures.count, fixture.outcomes.filter { $0 != "valid" }.count)
    }
  }

  func testFailureNoticeAndExistingHistoryRenderWithoutOpeningAWindow() throws {
    for dark in [false, true] {
      let center = LocalNoticeCenter(); defer { center.clearAll() }
      let report = WebsiteConfigInitializationReport(notices: center)
      for attempt in 1...3 {
        let error = NSError(domain: "Owned", code: attempt, userInfo: [NSLocalizedDescriptionKey: "自有内容来源暂时不可用，请检查网络后重新开始。"])
        report.record(WebsiteConfigInitializationReport.generation(attempt: attempt, error: error, quote: nil), whileCurrent: { true })
      }
      report.finish()
      var retries = 0
      let view = VStack(alignment: .leading, spacing: 16) {
        WebsiteConfigInitializationNotice(message: report.finalMessage!) { retries += 1 }
        LocalNoticeStack(center: center, focused: true)
      }.padding(16).frame(width: 600, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(dark ? .dark : .light)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 640),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      defer { window.contentView = nil; window.close() }
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      XCTAssertLessThanOrEqual(host.fittingSize.height, 640)
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: "/tmp/typebar-init-feedback-\(dark ? "dark" : "light").png"))
      XCTAssertFalse(window.isVisible); XCTAssertEqual(retries, 0); XCTAssertGreaterThan(png.count, 1000)
    }
  }
}
