import XCTest
import Observation
import AppKit
import SwiftUI
@testable import Typebar

@MainActor final class WebsiteConfigImportWorkflowTests: XCTestCase {
  private enum Failure: Error, Equatable { case notParked, provider }
  func testDeferredNextModeReadsCurrentWordAfterAcceptedSetterAndKeepsAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    var pending: [(Int, @MainActor () -> Void)] = []
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, dispatchKeymapHighlight: { pending.append(($0, $1)) },
      loadQuotes: { _ in [.init(id: "owned", title: "Owned", text: "ab 🙂x tail", language: .english, length: .short)] })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"keymapMode":"static","blindMode":true}"#, systemIsDark: false)
    let words = f.page.state.session.prompt.split(separator: " ").map(String.init)
    var state = f.page.state; state.session.insertBatch(words[0]); f.page.replace(state)
    let attempt = f.page.state.session.automaticInputAttemptID
    try await workflow.editAndBegin(.keymap(.display(.mode(.next))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(pending.map(\.0), [0])
    XCTAssertNil(f.page.state.session.websiteKeymapHighlightUnits, "Static input has no event; next setter must defer its callback")
    state = f.page.state; state.session.insertBatch(" "); f.page.replace(state)
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [55357], "Word-change input update uses one UTF-16 unit")
    try await workflow.editAndBegin(.keymap(.display(.mode(.staticGuide))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    pending.forEach { $0.1() }
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, words[1].unicodeScalars.first.map { Array(String($0).utf16) })
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
  }

  func testDeferredFluidWordsSchedulesWithoutLayoutBoundaryAndMapsPastWordToSpace() async throws {
    let f = try Fixture(); defer { f.close() }
    var pending: [(Int, @MainActor () -> Void)] = []
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, dispatchKeymapHighlight: { pending.append(($0, $1)) })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"keymapMode":"static","blindMode":true,"funbox":["layoutfluid"],"customLayoutfluid":["qwerty","colemak"]}"#, systemIsDark: false)
    let words = f.page.state.session.prompt.split(separator: " ").map(String.init)
    var state = f.page.state; state.session.insertBatch(words[0] + " "); f.page.replace(state)
    let original = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    try workflow.advanceLayoutFluid(.words(completed: 1, total: 10), attemptID: f.page.state.session.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, original)
    XCTAssertEqual(pending.map(\.0), [1])
    state = f.page.state; state.session.insertBatch(String(repeating: "x", count: words[1].utf16.count + 2)); f.page.replace(state)
    pending.forEach { $0.1() }
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [32])
  }

  func testDeferredFluidTimerSchedulesOnlyChangedLayoutWithNextEnabled() async throws {
    for mode in ["static", "next"] {
      let f = try Fixture(); defer { f.close() }
      var pending: [(Int, @MainActor () -> Void)] = []
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, dispatchKeymapHighlight: { pending.append(($0, $1)) })
      defer { workflow.stop() }
      try await workflow.apply(json: "{\"mode\":\"time\",\"time\":10,\"keymapMode\":\"\(mode)\",\"blindMode\":true,\"funbox\":[\"layoutfluid\"],\"customLayoutfluid\":[\"qwerty\",\"colemak\"]}", systemIsDark: false)
      var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
      let attempt = f.page.state.session.automaticInputAttemptID
      try workflow.advanceLayoutFluid(.time(1), attemptID: attempt)
      XCTAssertTrue(pending.isEmpty)
      try workflow.advanceLayoutFluid(.time(5), attemptID: attempt)
      XCTAssertEqual(pending.map(\.0), mode == "next" ? [1] : [])
      state = f.page.state; state.session.insertBatch(String(repeating: "x", count: 30)); f.page.replace(state)
      pending.forEach { $0.1() }
      if mode == "next" { XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [32]) }
      else { XCTAssertNil(f.page.state.session.websiteKeymapHighlightUnits) }
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    }
  }

  func testDeferredCallbacksRejectRetiredOwnershipButKeepAcceptedWorkAfterFormCancel() async throws {
    for retirement in ["stop", "detach", "reattach", "attempt", "ownerABA", "window", "cancel"] {
      let f = try Fixture(); defer { f.close() }
      var pending: [@MainActor () -> Void] = [], windowAvailable = true
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { windowAvailable ? f.window : nil }, dispatchKeymapHighlight: { _, action in pending.append(action) })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":10,"keymapMode":"static"}"#, systemIsDark: false)
      try await workflow.editAndBegin(.keymap(.display(.mode(.next))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertEqual(pending.count, 1)
      switch retirement {
      case "stop": workflow.stop()
      case "detach": f.page.detach()
      case "reattach": f.page.detach(); f.page.attach(to: f.settings.preferenceConfigurationSaves)
      case "attempt":
        var state = f.page.state; state.session = TypingSession(configuration: .words(100), prompt: "fresh tail")
        state.session.insertBatch("x"); f.page.replace(state)
      case "ownerABA":
        let other = UUID(), router = f.settings.preferenceConfigurationSaves
        router.register(owner: other, save: {}); router.activate(owner: other); router.activate(owner: f.page.owner)
      case "window": windowAvailable = false
      case "cancel": workflow.cancel()
      default: XCTFail("Unknown retirement")
      }
      let before = f.page.state.session.websiteKeymapHighlightUnits
      pending.forEach { $0() }
      if retirement == "cancel" {
        XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, f.page.state.session.prompt.unicodeScalars.first.map { Array(String($0).utf16) })
      } else { XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, before, retirement) }
    }
  }

  func testDeferredAcceptedCallbackIsOneShotWithoutCoalescing() async throws {
    let f = try Fixture(); defer { f.close() }
    var pending: [@MainActor () -> Void] = []
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, dispatchKeymapHighlight: { _, action in pending.append(action) },
      loadQuotes: { _ in [.init(id: "owned", title: "Owned", text: "ab cd tail", language: .english, length: .short)] })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"keymapMode":"static"}"#, systemIsDark: false)
    for _ in 0..<2 {
      try await workflow.editAndBegin(.keymap(.display(.mode(.next))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    }
    XCTAssertEqual(pending.count, 2, "Accepted equal setters keep separate source events")
    pending.first?()
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [97])
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [98])
    pending.first?()
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [98], "Replayed delivery cannot reset input")
    pending.last?()
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [97], "A distinct accepted delivery still executes")
  }

  func testDeferredDefaultMainQueueDispatchUpdatesTheActualWorkflow() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window },
      loadQuotes: { _ in [.init(id: "owned", title: "Owned", text: "ab cd tail", language: .english, length: .short)] })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"keymapMode":"static"}"#, systemIsDark: false)
    try await workflow.editAndBegin(.keymap(.display(.mode(.next))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while f.page.state.session.websiteKeymapHighlightUnits != [97], ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(f.page.state.session.websiteKeymapHighlightUnits, [97])
  }
  func testLayoutFluidHandlerFollowsProducingWorkflowAndRetiresOnStopOrDetach() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"time","time":10,"funbox":["layoutfluid"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let attempt = f.page.state.session.automaticInputAttemptID
    try f.page.advanceLayoutFluid(.time(4), attemptID: attempt)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let unrelated = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window })
    unrelated.stop()
    try f.page.advanceLayoutFluid(.time(5), attemptID: attempt)
    f.workflow.stop()
    do { try f.page.advanceLayoutFluid(.time(6), attemptID: attempt); XCTFail("Stopped handler retained") }
    catch PracticePageSessionStateError.stale {}
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    f.page.detach()
    do { try f.page.advanceLayoutFluid(.time(6), attemptID: attempt); XCTFail("Detached callback admitted") }
    catch PracticePageSessionStateError.stale {}
  }
  func testLayoutFluidTimeChangesOnlyRuntimeAndWordsSaveEachAcceptedSetter() async throws {
    for noQuit in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let boxes = noQuit ? "[\"layoutfluid\",\"no_quit\"]" : "[\"layoutfluid\"]"
      try await f.workflow.apply(json: "{\"mode\":\"time\",\"time\":10,\"customLayoutfluid\":[\"qwerty\",\"colemak\",\"dvorak\"],\"funbox\":\(boxes)}", systemIsDark: false)
      var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
      let before = f.page.state.session.generationState, original = try XCTUnwrap(f.page.state.presentation).publication
      try f.workflow.advanceLayoutFluid(.time(4), attemptID: before.attempt)
      let changed = try XCTUnwrap(f.page.state.presentation).publication
      XCTAssertEqual(changed.draft.keyboardTypography.inputLayout.emulatedLayout, noQuit ? .ansiQwerty : .ansiColemak)
      XCTAssertEqual(changed.draft.keyboardTypography.guideLayout, .ansiColemak)
      XCTAssertEqual(changed.savedDraft.projection.runtime, original.savedDraft.projection.runtime)
      XCTAssertEqual(changed.disk, original.disk); XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, original.disk)
      XCTAssertEqual(f.page.state.session.generationState, before)
      try await f.workflow.editAndBegin(.keymap(.size(1.5)), replacing: changed.applicationID, systemIsDark: false)
      guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing saved runtime") }
      XCTAssertEqual(saved["layout"], .string(noQuit ? "qwerty" : "colemak")); XCTAssertEqual(saved["keymapLayout"], .string("colemak"))
    }
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["layoutfluid","no_quit"],"customLayoutfluid":["qwerty","colemak","dvorak"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    try f.workflow.advanceLayoutFluid(.words(completed: 3, total: 10), attemptID: before.attempt)
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertNotEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.inputLayout.emulatedLayout, .ansiQwerty)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideLayout, .ansiColemak)
    XCTAssertTrue(try XCTUnwrap(f.account.localNotices.active.first).important)
  }
  func testLayoutFluidLateAttemptAndCompetingFileCannotPublishVolatileChanges() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"time","time":10,"funbox":["layoutfluid"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = try XCTUnwrap(f.page.state.presentation).publication
    do { try f.workflow.advanceLayoutFluid(.time(5), attemptID: UUID()); XCTFail("Late callback admitted") }
    catch WebsiteConfigImportWorkflowError.unavailable {}
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":7}"#, pointsPerRem: 16, context: .init())
    _ = try register.commit(other, replacing: XCTUnwrap(register.read().revision))
    do { try f.workflow.advanceLayoutFluid(.time(5), attemptID: f.page.state.session.automaticInputAttemptID); XCTFail("Competing file ignored") } catch {}
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, before.applicationID)
  }
  func testKeymapSizeFormUsesPublicationAndFitsHiddenLightAndDarkLayoutsWithoutSaving() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"keymapSize":2.1}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let presentation = WebsiteKeymapSizePresentation(publication: publication)
    XCTAssertEqual(presentation.id, publication.applicationID); XCTAssertEqual(presentation.initialText, "2.1")
    var calls = 0
    for (width, dark) in [(440.0, false), (640.0, true)] {
      let view = WebsiteKeymapSizeCommandView(presentation: presentation, canApply: true, apply: { _ in calls += 1 })
        .frame(width: width, height: 320).background(dark ? Color(white: 0.12) : .white)
        .environment(\.colorScheme, dark ? .dark : .light)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 320), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      try await Task.sleep(for: .milliseconds(50))
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-keymap-size-\(Int(width))-\(dark ? "dark" : "light").png"))
      XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
      window.contentView = nil; window.close()
    }
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, publication.disk)
  }
  func testKeymapDisplayCommandsSaveDuringNoQuitWithoutChangingTheAttemptOrInputMapping() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"layout":"colemak","funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    let targets = KeyboardGuideCommandCatalog.items.compactMap { KeyboardGuideCommandCatalog.target(for: $0.id) }.map(WebsiteKeymapCommandTarget.display)
    for target in targets + [.size(1.6), .layout(.builtIn(.ansiDvorak)), .layout(.inputSync)] {
      let count = f.account.localNotices.history.count
      try await f.workflow.editAndBegin(.keymap(target), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      XCTAssertEqual(publication.draft.projection.runtime[target.key], target.value)
      XCTAssertEqual(publication.draft.keyboardTypography.inputLayout.emulatedLayout, .ansiColemak)
      XCTAssertEqual(f.page.state.session.generationState, before); XCTAssertEqual(f.settings.snapshot, legacy)
      XCTAssertEqual(f.account.localNotices.history.count, count + (target.requestsRestart ? 1 : 0))
      if target.requestsRestart { XCTAssertTrue(try XCTUnwrap(f.account.localNotices.active.first).important) }
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(publication.draft.projection.runtime))
    }
  }
  func testKeymapLayoutSavesThenRestartsButDisplayAndSizeRetainTheActiveAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"layout":"colemak"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot
    try await f.workflow.editAndBegin(.keymap(.display(.style(.matrix))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .staticGuide)
    try await f.workflow.editAndBegin(.keymap(.layout(.builtIn(.ansiDvorak))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before.attempt)
    XCTAssertTrue(f.page.state.session.typed.isEmpty)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideLayout, .ansiDvorak)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.inputLayout.emulatedLayout, .ansiColemak)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testKeymapSecondSetterConflictRetainsTheAcceptedEnable() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var compete = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if compete, f.page.state.presentation?.publication.draft.keyboardTypography.guideMode == .staticGuide {
          compete = false
          do { _ = try register.commit(other, replacing: XCTUnwrap(register.read().revision)) } catch { XCTFail("Competitor: \(error)") }
        }
        return f.window
      }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"keymapMode":"off"}"#, systemIsDark: false)
    let before = f.page.state.session.generationState
    compete = true
    do { try await workflow.editAndBegin(.keymap(.display(.style(.matrix))), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("Overwrote competitor") }
    catch WebsiteKeymapCommandError.interrupted(let saved, _) { XCTAssertEqual(saved, 1) }
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .staticGuide)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideStyle, .staggered)
    XCTAssertEqual(f.page.state.session.generationState, before)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing competitor") }
    XCTAssertEqual(saved["words"], .number(7))
  }
  func testKeymapInvalidCancelledAndStaleCommandsCannotWriteOrRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication, before = f.page.state.session.generationState
    for value in [0.0, 0.51, 3.6, Double.infinity] {
      do { try await f.workflow.editAndBegin(.keymap(.size(value)), replacing: original.applicationID, systemIsDark: false); XCTFail("Invalid size saved") }
      catch WebsiteKeymapCommandError.invalidInput {}
    }
    let task = Task { @MainActor in try await f.workflow.editAndBegin(.keymap(.layout(.inputSync)), replacing: original.applicationID, systemIsDark: false) }
    task.cancel(); do { _ = try await task.value; XCTFail("Cancelled keymap saved") } catch is CancellationError {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, original.disk)
    try await f.workflow.editAndBegin(.keymap(.size(1.5)), replacing: original.applicationID, systemIsDark: false)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    do { try await f.workflow.editAndBegin(.keymap(.layout(.inputSync)), replacing: original.applicationID, systemIsDark: false); XCTFail("Stale keymap saved") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, current.disk)
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(WebsiteKeymapSizePresentation(publication: current).initialText, "1.5")
  }
  func testAppearanceHighlightRedrawClearsStoppedGlyphWithoutChangingAcceptedInput() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"stopOnError":"letter"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("☃"); f.page.replace(state)
    let before = f.page.state.session
    XCTAssertTrue(before.promptGlyphs.contains { $0.typedCharacter == "☃" }); XCTAssertTrue(before.typed.isEmpty)
    try await f.workflow.editAndBegin(.appearance(.color(.accent)), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertTrue(f.page.state.session.promptGlyphs.contains { $0.typedCharacter == "☃" })
    try await f.workflow.editAndBegin(.appearance(.highlight(.word)), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertFalse(f.page.state.session.promptGlyphs.contains { $0.typedCharacter == "☃" })
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.characterStats, before.characterStats)
  }
  func testAppearanceBlockedOptionsDoNotSaveAndPostOneOrdinaryNotice() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["arrows","no_quit"],"tapeMode":"word"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    for command in [AppearanceCommandTarget.showAllLines(true), .highlight(.word)] {
      let publication = try XCTUnwrap(f.page.state.presentation).publication, before = f.page.state.session.generationState
      let count = f.account.localNotices.history.count
      try await f.workflow.editAndBegin(.appearance(command), replacing: publication.applicationID, systemIsDark: false)
      XCTAssertEqual(f.account.localNotices.history.count, count + 1)
      XCTAssertFalse(try XCTUnwrap(f.account.localNotices.active.first).important)
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, publication.disk)
      XCTAssertEqual(f.page.state.session.generationState, before)
    }
  }
  func testAllAppearanceMenuOptionsSaveWithoutRestartAndWphStaysImportable() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot
    let commands = AppearanceCommandCatalog.items.compactMap { AppearanceCommandCatalog.target(for: $0.id) }
    XCTAssertEqual(commands.count, 48)
    for command in commands + [.speedUnit(.wph)] {
      if command == .showAllLines(true) {
        try await f.workflow.editAndBegin(.appearance(.tape(.off)), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      }
      try await f.workflow.editAndBegin(.appearance(command), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime[command.websiteKey], command.websiteValue)
      XCTAssertEqual(f.page.state.session.generationState, before)
    }
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testAppearanceSecondSetterConflictRetainsItsAcceptedCompanionChange() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var compete = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if compete, f.page.state.presentation?.publication.draft.presentation.showTypingCompanion == false {
          compete = false
          do { _ = try register.commit(other, replacing: XCTUnwrap(register.read().revision)) }
          catch { XCTFail("Competing writer: \(error)") }
        }
        return f.window
      }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"monkey":true,"liveSpeedStyle":"mini"}"#, systemIsDark: false)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot
    compete = true
    do {
      try await workflow.editAndBegin(.appearance(.speed(.text)), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Appearance overwrote competitor")
    } catch WebsiteAppearanceCommandError.interrupted(let saved, _) { XCTAssertEqual(saved, 1) }
    XCTAssertFalse(try XCTUnwrap(f.page.state.presentation).publication.draft.presentation.showTypingCompanion)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.presentation.liveSpeedStyle, .mini)
    XCTAssertEqual(f.page.state.session.generationState, before); XCTAssertEqual(f.settings.snapshot, legacy)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Lost competitor") }
    XCTAssertEqual(saved["words"], .number(7))
  }
  func testCancelledAndStaleAppearanceCommandsCannotWriteOrReplaceTheAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication, before = f.page.state.session.generationState
    let task = Task { @MainActor in try await f.workflow.editAndBegin(.appearance(.color(.black)), replacing: original.applicationID, systemIsDark: false) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled appearance saved") } catch is CancellationError {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, original.disk)
    try await f.workflow.editAndBegin(.appearance(.color(.black)), replacing: original.applicationID, systemIsDark: false)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    do { try await f.workflow.editAndBegin(.appearance(.speedUnit(.cpm)), replacing: original.applicationID, systemIsDark: false); XCTFail("Stale appearance saved") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, current.disk)
    XCTAssertEqual(f.page.state.session.generationState, before)
  }
  func testAppearanceCommandsSaveOwnedProfileWithoutRestartingActiveNoQuit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"],"monkey":true,"showAllLines":true}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot, controller = f.page.restartController
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    for command in [AppearanceCommandTarget.speed(.text), .tape(.word), .speedUnit(.cpm), .color(.accent), .opacity(.half), .progress(.mini)] {
      try await f.workflow.editAndBegin(.appearance(command), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
      XCTAssertEqual(draft.projection.runtime[command.websiteKey], command.websiteValue)
      XCTAssertEqual(f.page.state.session.generationState, before); XCTAssertTrue(f.page.restartController === controller)
      XCTAssertEqual(f.settings.snapshot, legacy)
    }
    let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(draft.presentation.showTypingCompanion); XCTAssertFalse(draft.presentation.showAllPracticeLines)
    XCTAssertEqual(draft.presentation.practiceTapeMode, .word)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("No appearance profile") }
    XCTAssertEqual(saved, draft.projection.runtime)
  }
  func testPaceFormSnapshotAndHiddenLayoutDoNotApplyConfiguration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"typingSpeedUnit":"cpm","paceCaretCustomSpeed":80}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let presentation = WebsitePaceSpeedPresentation(publication: publication)
    XCTAssertEqual(presentation.id, publication.applicationID); XCTAssertEqual(presentation.initialText, "80"); XCTAssertEqual(presentation.unit, .cpm)
    for (width, dark) in [(440.0, false), (640.0, true)] {
      var calls = 0
      let view = WebsitePaceSpeedCommandView(presentation: presentation, canApply: true, apply: { _ in calls += 1 })
        .frame(width: width, height: 280).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 280), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
      defer { window.contentView = nil; window.close() }
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-pace-speed-\(Int(width))-\(dark ? "dark" : "light").png"))
      XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
    }
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, publication.disk)
  }
  func testCancelledPaceCommandCannotSaveOrRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication, before = f.page.state.session.automaticInputAttemptID
    let task = Task { @MainActor in try await f.workflow.runPaceCommand(.mode(.off), replacing: original.applicationID) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled pace command saved") } catch is CancellationError {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, original.disk)
  }
  func testPaceRejectedAccountSelectionStillRestartsTheOriginalConfiguration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"paceCaret":"last"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.automaticInputAttemptID, legacy = f.settings.snapshot
    try await f.workflow.runPaceCommand(.mode(.personalBest), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.behavior.paceGuideMode, .lastTest)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.settings.snapshot, legacy)
    XCTAssertTrue(f.account.localNotices.active.contains { !$0.important })
  }
  func testPaceCommandsRejectInvalidAndStaleInputsBeforeWritingAndUseProfileUnit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"typingSpeedUnit":"cpm"}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication
    for input in ["-1", "NaN", "80tail", "Infinity"] {
      do { try await f.workflow.runPaceCommand(.customSpeed, input: input, replacing: original.applicationID); XCTFail("Invalid pace saved") }
      catch is WebsitePaceCommandError {}
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, original.disk)
    }
    try await f.workflow.runPaceCommand(.customSpeed, input: "600", replacing: original.applicationID)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertEqual(current.draft.behavior.paceGuideCustomWpm, 120); XCTAssertEqual(current.draft.behavior.paceGuideMode, .custom)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, original.session?.automaticInputAttemptID)
    do { try await f.workflow.runPaceCommand(.mode(.off), replacing: original.applicationID); XCTFail("Stale command saved") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, current.applicationID)
  }
  func testPaceSecondSetterConflictRetainsTheFirstAcceptedSelection() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var compete = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if compete, f.page.state.presentation?.publication.draft.behavior.paceGuideMode == .custom {
          compete = false
          do { _ = try register.commit(other, replacing: XCTUnwrap(register.read().revision)) }
          catch { XCTFail("Competing writer: \(error)") }
        }
        return f.window
      }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"paceCaret":"off","paceCaretCustomSpeed":80}"#, systemIsDark: false)
    let before = f.page.state.session.automaticInputAttemptID
    compete = true
    do { try await workflow.runPaceCommand(.customSpeed, input: "120", replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID); XCTFail("Overwrote competitor") }
    catch WebsitePaceCommandError.interrupted(let saved, _) { XCTAssertEqual(saved, 1) }
    XCTAssertEqual(f.page.state.presentation?.publication.draft.behavior.paceGuideMode, .custom)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.behavior.paceGuideCustomWpm, 80)
    XCTAssertEqual(f.page.state.session.paceCaretTargetWpm, 80)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Lost competitor") }
    XCTAssertEqual(saved["words"], .number(7))
  }
  func testPaceCustomSavesInSourceOrderWhileNoQuitBlocksOnlyRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"],"paceCaret":"off","paceCaretCustomSpeed":80}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session, legacy = f.settings.snapshot
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    try await f.workflow.runPaceCommand(.customSpeed, input: "120", replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.behavior.paceGuideCustomWpm, 120)
    XCTAssertEqual(f.page.state.session.paceCaretTargetWpm, 80, "The mode event initializes before the speed setter")
    try await f.workflow.runPaceCommand(.customSpeed, input: "160", replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID)
    XCTAssertEqual(f.page.state.session.paceCaretTargetWpm, 80, "A speed-only event does not initialize pace")
    XCTAssertEqual(f.settings.snapshot, legacy)
    XCTAssertEqual(f.account.localNotices.active.filter { $0.important }.count, 2)
  }
  func testCaretCompetingRecordDoesNotInstallItsCandidateStyle() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var writeOnRead = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if writeOnRead {
          writeOnRead = false
          do {
            guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
              XCTFail("No competing record"); return f.window
            }
          } catch { XCTFail("Competing writer: \(error)") }
        }
        return f.window
      }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"caretStyle":"underline"}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication, before = f.page.state.session.generationState
    writeOnRead = true
    do {
      try await workflow.editAndBegin(.caret(.primary(.block)), replacing: original.applicationID, systemIsDark: false)
      XCTFail("Caret write overwrote competitor")
    } catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, original.applicationID)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.presentation.caretStyle, .underline)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Lost competitor") }
    XCTAssertEqual(saved["words"], .number(7))
  }
  func testCaretRepeatPreferenceAppliesOnlyToExplicitNextRepeat() async throws {
    for enabled in [false, true] {
      let f = try Fixture(); defer { f.close() }
      var reads = 0
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadExternal: { _, _, _, _ in
          reads += 1
          return .init(source: .encyclopedia, initial: .init(text: "ab cd", noSpaceBoundarySource: nil), continuation: nil)
        }); defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":2,"funbox":["wikipedia"]}"#, systemIsDark: false)
      var complete = f.page.state
      complete.session.insertBatch(complete.session.prompt + " "); f.page.replace(complete)
      XCTAssertTrue(f.page.state.session.isFinished)
      let before = f.page.state.session.generationState
      try await workflow.editAndBegin(.caret(.repeatedPace(enabled)),
        replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertEqual(f.page.state.session.generationState, before)
      let advanced = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID(), repeatingRequested: true)
      XCTAssertTrue(advanced); XCTAssertEqual(reads, 1)
      XCTAssertEqual(f.page.state.practice?.repetition.repeatsPace, enabled)
    }
  }
  func testCaretStaleAndCancelledCommandsCannotReplaceTheLivePublication() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication
    try await f.workflow.editAndBegin(.caret(.primary(.block)), replacing: original.applicationID, systemIsDark: false)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    let before = f.page.state.session.generationState
    do {
      try await f.workflow.editAndBegin(.caret(.primary(.off)), replacing: original.applicationID, systemIsDark: false)
      XCTFail("Stale caret command saved")
    } catch WebsiteConfigImportWorkflowError.conflict {}
    let task = Task { @MainActor in
      try await f.workflow.editAndBegin(.caret(.primary(.off)), replacing: current.applicationID, systemIsDark: false)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled caret command saved") } catch is CancellationError {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, current.applicationID)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, current.disk)
  }
  func testCaretCommandsPublishLiveStylesWithoutRestartingOrWritingLegacySettings() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot
    let controller = f.page.restartController
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    let commands = CaretCommandCatalog.items.compactMap { CaretCommandCatalog.target(for: $0.id) }
    XCTAssertEqual(commands.count, 22)
    for command in commands {
      try await f.workflow.editAndBegin(.caret(command), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
      switch command {
      case .smooth(let value): XCTAssertEqual(draft.presentation.smoothCaretMotion, value)
      case .primary(let value): XCTAssertEqual(draft.presentation.caretStyle, value)
      case .pace(let value): XCTAssertEqual(draft.presentation.paceCaretStyle, value)
      case .repeatedPace(let value): XCTAssertEqual(draft.behavior.repeatedPace, value)
      }
      XCTAssertEqual(f.page.state.session.generationState, before)
      XCTAssertTrue(f.page.restartController === controller)
      XCTAssertEqual(f.settings.snapshot, legacy)
      guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("No saved caret profile") }
      XCTAssertEqual(saved, draft.projection.runtime)
    }
  }
  func testAllCanonicalSoundOptionsSaveWithoutRestartAndUnsupportedValuesCannotWrite() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState, legacy = f.settings.snapshot
    let targets = SoundCommandCatalog.items.compactMap { SoundCommandCatalog.target(for: $0.id) }.filter { $0.websiteValue != .null }
    XCTAssertEqual(targets.count, 40)
    for target in targets {
      try await f.workflow.editAndBegin(.sound(target), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime[target.websiteKey], target.websiteValue)
      XCTAssertEqual(f.page.state.session.generationState, before)
    }
    let current = try XCTUnwrap(f.page.state.presentation).publication
    for value in [-0.1, 1.1, Double.infinity, Double.nan] {
      do {
        try await f.workflow.editAndBegin(.sound(.volume(value)), replacing: current.applicationID, systemIsDark: false)
        XCTFail("Invalid volume saved")
      } catch WebsiteConfigNativeDraftError.rejectedEdit {}
    }
    do {
      try await f.workflow.editAndBegin(.sound(.click(.ripple)), replacing: current.applicationID, systemIsDark: false)
      XCTFail("Native extension written into canonical profile")
    } catch WebsiteSoundCommandError.unsupportedTone {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, current.disk)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testSoundCASConflictDoesNotInstallCandidateOrChangeTheCompetingRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var writeOnRead = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if writeOnRead {
          writeOnRead = false
          do {
            guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
              XCTFail("No competing record"); return f.window
            }
          } catch { XCTFail("Competing writer: \(error)") }
        }
        return f.window
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"soundVolume":0.37}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation).publication, before = f.page.state.session.generationState
    writeOnRead = true
    do {
      try await workflow.editAndBegin(.sound(.volume(0.1)), replacing: original.applicationID, systemIsDark: false)
      XCTFail("Sound write overwrote competitor")
    } catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, original.applicationID)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Lost competitor") }
    XCTAssertEqual(saved["words"], .number(7))
  }
  func testVolumeCommandSnapshotAndHiddenLayoutDoNotApplyOrPlayAudio() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"soundVolume":0.37}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let presentation = WebsiteSoundVolumePresentation(publication: publication)
    XCTAssertEqual(presentation.id, publication.applicationID); XCTAssertEqual(presentation.initialText, "0.37")
    for (width, dark) in [(440.0, false), (640.0, true)] {
      var calls = 0
      let view = WebsiteSoundVolumeCommandView(presentation: presentation, canApply: true, apply: { _ in calls += 1 })
        .frame(width: width, height: 260).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 260), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
      defer { window.contentView = nil; window.close() }
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: "/tmp/typebar-sound-volume-\(Int(width))-\(dark ? "dark" : "light").png"))
      XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
    }
  }
  func testSoundCommandsRetainActiveNoQuitAttemptAndSaveOnlyTheOwnedProfile() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session.generationState
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    for target in [SoundCommandTarget.volume(0.37), .click(.pianoSine), .error(.basso), .timeWarning(.threeSeconds), .click(nil)] {
      try await f.workflow.editAndBegin(.sound(target), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime[target.websiteKey], target.websiteValue)
      XCTAssertEqual(f.page.state.session.generationState, before)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    }
    XCTAssertEqual(f.settings.snapshot, legacy)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing sound profile") }
    XCTAssertEqual(saved["soundVolume"], .number(0.37)); XCTAssertEqual(saved["playSoundOnClick"], .string("off"))
  }
  func testInputStepAdmissionRejectsRestartMarkedFieldsAndCompoundOverridesDuringNoQuit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"freedomMode":true,"stopOnError":"word","funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let router = f.settings.preferenceConfigurationSaves, lease = try XCTUnwrap(f.settings.preferenceConfigurationSaves.captureLease())
    let capture = try f.page.captureGeneration(router: router)
    for (key, value) in [("strictSpace", WebsiteConfigValue.bool(true)), ("codeUnindentOnBackspace", .bool(true)),
      ("stopOnError", .string("off")), ("confidenceMode", .string("on")), ("minWpmCustomSpeed", .number(0))] {
      let draft = try WebsiteConfigNativeProfile.editDraft(capture.publication.draft, key: key, value: value,
        pointsPerRem: 16, context: .init(), testActive: false)
      XCTAssertThrowsError(try f.page.beginLiveInputRuleCommit(owner: lease, router: router, capture: capture, draft: draft))
      XCTAssertTrue(f.page.acceptsAttemptCallback(for: state.session.automaticInputAttemptID))
    }
    let allowed = try WebsiteConfigNativeProfile.editDraft(capture.publication.draft, key: "freedomMode", value: .bool(false),
      pointsPerRem: 16, context: .init(), testActive: true)
    try f.page.beginLiveInputRuleCommit(owner: lease, router: router, capture: capture, draft: allowed)
    f.page.endCommit()
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
  }
  func testInputLazyCommandAloneRestartsAndNoQuitProducesBothRefusals() async throws {
    for noQuit in [false, true] {
      let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
      let json = noQuit ? #"{"mode":"words","words":10,"language":"german","funbox":["no_quit"]}"# : #"{"mode":"words","words":10,"language":"german"}"#
      try await f.workflow.apply(json: json, systemIsDark: false)
      var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
      let old = try XCTUnwrap(f.page.state.presentation).publication
      let count = f.account.localNotices.history.count
      if noQuit {
        let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
        defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
        do {
          try await f.workflow.editAndBegin(.inputRule(.lazyMode(true)), replacing: old.applicationID, systemIsDark: false)
          XCTFail("No Quit restarted")
        } catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
        XCTAssertEqual(f.account.localNotices.history.count - count, 2)
        XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
        XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, old.disk)
      } else {
        try await f.workflow.editAndBegin(.inputRule(.lazyMode(true)), replacing: old.applicationID, systemIsDark: false)
        XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, state.session.automaticInputAttemptID)
        XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
        XCTAssertTrue(f.page.state.session.configuration.modifiers.contains(.lazyLatin))
      }
    }
  }
  func testInputCommandsSaveAllNonLazyOptionsWithoutRestartingTheAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session, legacy = f.settings.snapshot
    let controller = f.page.restartController
    for target in InputRuleCommandCatalog.items.compactMap({ InputRuleCommandCatalog.target(for: $0.id) }) {
      if case .lazyMode = target { continue }
      try await f.workflow.editAndBegin(.inputRule(target), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      XCTAssertEqual(publication.draft.projection.runtime[target.websiteKey], target.websiteValue)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
      XCTAssertEqual(f.page.state.session.typed, before.typed); XCTAssertEqual(f.page.state.session.prompt, before.prompt)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0); XCTAssertTrue(f.page.restartController === controller)
      XCTAssertEqual(f.page.state.session.configuration.rules, publication.draft.inputRules.rules)
    }
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testInputCommandLaterCASConflictRetainsFirstSavedChildAndCompetingRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"freedomMode":true,"stopOnError":"word"}"#, systemIsDark: false)
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated {
        do {
          guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else { return XCTFail("No competitor") }
        } catch { XCTFail("Competing record: \(error)") }
      }
    }
    do {
      try await f.workflow.editAndBegin(.inputRule(.confidenceMode(.on)), replacing: id, systemIsDark: false)
      XCTFail("Competing record overwritten")
    } catch WebsiteInputCommandError.interrupted(let saved, _) { XCTAssertEqual(saved, 1) }
    XCTAssertFalse(f.page.state.session.configuration.rules.freedomMode)
    XCTAssertEqual(f.page.state.session.configuration.rules.stopOnErrorMode, .word)
    XCTAssertEqual(f.page.state.session.configuration.rules.confidenceMode, .off)
    guard case .available(let runtime) = try register.read().state else { return XCTFail("Lost record") }
    XCTAssertEqual(runtime["words"], .number(7))
  }
  func testFinishedInputRulesStayImmutableAndRepeatUsesCurrentStrictStopAndCodeRules() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { _, _, _, _ in
        reads += 1; return .init(source: .encyclopedia, initial: .init(text: "ab cd", noSpaceBoundarySource: nil), continuation: nil)
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":2,"funbox":["wikipedia"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch(state.session.prompt + " "); f.page.replace(state)
    let before = f.page.state.session
    XCTAssertTrue(before.isFinished)
    for target in [InputRuleCommandTarget.strictSpace(true), .stopOnError(.word), .codeUnindentOnBackspace(true)] {
      try await workflow.editAndBegin(.inputRule(target), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertEqual(f.page.state.session.generationState, before.generationState)
    }
    let repeated = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(repeated); XCTAssertEqual(reads, 1); XCTAssertEqual(f.page.state.session.prompt, before.prompt)
    XCTAssertTrue(f.page.state.session.configuration.rules.strictSpace)
    XCTAssertEqual(f.page.state.session.configuration.rules.stopOnErrorMode, .word)
    XCTAssertTrue(f.page.state.session.configuration.rules.codeUnindentOnBackspace)
  }
  func testInputCommandStrictSpaceDoesNotRestartOrWriteLegacyPreferences() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session
    try await f.workflow.editAndBegin(.inputRule(.strictSpace(true)),
      replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertTrue(f.page.state.session.configuration.rules.strictSpace)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testInputCommandFailedOverrideKeepsPreviouslySavedChild() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"freedomMode":true,"stopOnError":"word","funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    XCTAssertTrue(f.page.state.session.configuration.rules.freedomMode)
    let before = f.page.state.session.automaticInputAttemptID
    do {
      try await f.workflow.editAndBegin(.inputRule(.confidenceMode(.on)),
        replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Blocked override reported success")
    } catch {}
    XCTAssertFalse(f.page.state.session.configuration.rules.freedomMode)
    XCTAssertEqual(f.page.state.session.configuration.rules.stopOnErrorMode, .word)
    XCTAssertEqual(f.page.state.session.configuration.rules.confidenceMode, .off)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Lost record") }
    XCTAssertEqual(saved["freedomMode"], .bool(false))
  }
  func testAnotherWindowsNoQuitLockCannotGrantSelectionReadToAnUnlockedAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let before = f.page.state.session.generationState
    let original = try XCTUnwrap(f.page.state.presentation).publication
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    XCTAssertThrowsError(try f.workflow.runThresholdCommand(.minimumWpmOff, input: "", replacing: original.applicationID)) {
      guard case WebsiteConfigCommitCoordinatorError.noEnvironment = $0 else { return XCTFail("Unexpected error: \($0)") }
    }
    do {
      try await f.workflow.editAndBegin(.polyglotLanguages(["german", "spanish"]), replacing: original.applicationID, systemIsDark: false)
      XCTFail("Another window's lock was treated as owned No Quit")
    } catch WebsiteConfigCommitCoordinatorError.noEnvironment {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, original.disk)
  }

  func testLockedFuturePolyglotCASConflictKeepsAttemptAndDoesNotPostSavedNotice() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var writes = 0, writeOnRead = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if writeOnRead {
          writeOnRead = false
          do {
            guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
              XCTFail("No competing write"); return f.window
            }
            writes += 1
          } catch { XCTFail("Competing writer: \(error)") }
        }
        return f.window
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state; active.session.insertBatch("x"); f.page.replace(active)
    let old = try XCTUnwrap(f.page.state.presentation).publication
    let before = f.page.state.session.generationState
    let lock = UUID(); f.settings.setNoQuitConfigurationLock(true, for: lock)
    defer { f.settings.setNoQuitConfigurationLock(false, for: lock) }
    let notices = f.account.localNotices.history.count
    writeOnRead = true
    do {
      try await workflow.editAndBegin(.polyglotLanguages(["german", "spanish"]), replacing: old.applicationID, systemIsDark: false)
      XCTFail("Overwrote competing record")
    } catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(writes, 1); XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old.applicationID)
    XCTAssertEqual(f.account.localNotices.history.count, notices)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Competitor lost") }
    XCTAssertEqual(saved["words"], .number(7))
  }
  func testLiveBehaviorCASFailureDoesNotInstallItsCandidateRules() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var writes = 0, writeOnRead = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if writeOnRead {
          writeOnRead = false
          do {
            guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
              XCTFail("No competing CAS"); return f.window
            }
            writes += 1
          } catch { XCTFail("Competing writer: \(error)") }
        }
        return f.window
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let before = f.page.state.session.generationState
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    writeOnRead = true
    do {
      _ = try await workflow.editAndBegin(.behavior(.blindMode(true)), replacing: id, systemIsDark: false)
      XCTFail("Candidate replaced competing record")
    } catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(writes, 1); XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Competitor lost") }
    XCTAssertEqual(saved["words"], .number(7)); XCTAssertEqual(saved["blindMode"], .bool(false))
  }
  func testLiveBehaviorCancellationFromWindowCaptureCannotSave() async throws {
    let f = try Fixture(); defer { f.close() }
    var cancelOnRead = false
    var workflow: WebsiteConfigImportWorkflow?
    workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if cancelOnRead { workflow?.cancel() }
        return f.window
      })
    let owned = try XCTUnwrap(workflow)
    defer { owned.stop(); workflow = nil }
    try await owned.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let before = f.page.state.session.generationState
    cancelOnRead = true
    do {
      _ = try await owned.editAndBegin(.behavior(.blindMode(true)), replacing: publication.applicationID, systemIsDark: false)
      XCTFail("Retired callback committed")
    } catch is CancellationError {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, publication.disk)
  }
  func testLiveBehaviorAdmissionCannotBypassNoQuitForOtherFieldsOrImports() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state
    active.session.insertBatch(String(active.session.prompt.prefix(1))); f.page.replace(active)
    let router = f.settings.preferenceConfigurationSaves
    let capture = try f.page.captureGeneration(router: router)
    let lease = try XCTUnwrap(router.captureLease())
    for (key, value) in [("words", WebsiteConfigValue.number(20)), ("minWpmCustomSpeed", .number(73)),
      ("customPolyglot", .array([.string("german"), .string("spanish")]))] {
      let draft = try WebsiteConfigNativeProfile.editDraft(capture.publication.draft, key: key, value: value,
        pointsPerRem: 16, context: .init(), testActive: false)
      XCTAssertThrowsError(try f.page.beginLiveBehaviorCommit(owner: lease, router: router, capture: capture, draft: draft))
      XCTAssertTrue(f.page.acceptsAttemptCallback(for: active.session.automaticInputAttemptID))
    }
    let imported = try WebsiteConfigNativeProfile.prepareDraft(#"{"blindMode":true}"#, pointsPerRem: 16, context: .init())
    XCTAssertThrowsError(try f.page.beginLiveBehaviorCommit(owner: lease, router: router, capture: capture, draft: imported))
    let allowed = try WebsiteConfigNativeProfile.editDraft(capture.publication.draft, key: "blindMode", value: .bool(true),
      pointsPerRem: 16, context: .init(), testActive: true)
    try f.page.beginLiveBehaviorCommit(owner: lease, router: router, capture: capture, draft: allowed)
    XCTAssertFalse(f.page.acceptsAttemptCallback(for: active.session.automaticInputAttemptID)); f.page.endCommit()
    XCTAssertTrue(f.page.acceptsAttemptCallback(for: active.session.automaticInputAttemptID))
    XCTAssertEqual(f.page.state.session.typed, active.session.typed)
    XCTAssertFalse(f.page.state.session.configuration.rules.blindMode)
  }

  func testLiveBehaviorCompetingRecordAndCancelledTaskLeaveTheCurrentAttemptUntouched() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let before = f.page.state.session.generationState
    let task = Task { @MainActor in
      try await f.workflow.editAndBegin(.behavior(.blindMode(true)), replacing: publication.applicationID, systemIsDark: false)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled command saved") } catch is CancellationError {}
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertEqual(try register.read().revision, publication.disk)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try register.commit(other, replacing: publication.disk) else { return XCTFail("No competitor") }
    do {
      _ = try await f.workflow.editAndBegin(.behavior(.blindMode(true)), replacing: publication.applicationID, systemIsDark: false)
      XCTFail("Competing record overwritten")
    } catch {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Record lost") }
    XCTAssertEqual(saved["words"], .number(7)); XCTAssertEqual(saved["blindMode"], .bool(false))
  }

  func testFinishedResultKeepsBlindRuleButExplicitRepeatUsesSavedBehavior() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { _, _, _, _ in
        reads += 1
        return .init(source: .encyclopedia, initial: .init(text: "ab cd", noSpaceBoundarySource: nil), continuation: nil)
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":2,"funbox":["wikipedia"]}"#, systemIsDark: false)
    var complete = f.page.state
    complete.session.insertBatch(complete.session.prompt + " "); f.page.replace(complete)
    XCTAssertTrue(f.page.state.session.isFinished)
    let before = f.page.state.session
    try await workflow.editAndBegin(.behavior(.blindMode(true)),
      replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.generationState, before.generationState)
    XCTAssertFalse(f.page.state.session.configuration.rules.blindMode)
    let advanced = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(advanced); XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.session.prompt, before.prompt)
    XCTAssertTrue(f.page.state.session.configuration.rules.blindMode)
  }
  func testLiveBehaviorCommandsSaveWithoutRestartingAnActiveNoQuitAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state
    active.session.insertBatch(String(active.session.prompt.prefix(1))); f.page.replace(active)
    let original = f.page.state.session
    let controller = f.page.restartController
    for command in [BehaviorCommandTarget.blindMode(true), .quickRestart(.escape),
      .alwaysShowWordsHistory(true), .commandPaletteListMode(.singleList), .blindMode(false)] {
      let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
      _ = try await f.workflow.editAndBegin(.behavior(command), replacing: id, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      XCTAssertEqual(publication.draft.projection.runtime[command.websiteKey], command.websiteValue)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, original.automaticInputAttemptID)
      XCTAssertEqual(f.page.state.session.typed, original.typed); XCTAssertEqual(f.page.state.session.prompt, original.prompt)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
      XCTAssertTrue(f.page.restartController === controller)
      guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("No saved behavior") }
      XCTAssertEqual(saved[command.websiteKey], command.websiteValue)
      if case .blindMode(let enabled) = command {
        XCTAssertEqual(f.page.state.session.configuration.rules.blindMode, enabled)
      }
    }
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testThresholdCommandPresentationKeepsRawMemoryAndProfileUnitInHiddenNativeViews() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"typingSpeedUnit":"cpm","minWpmCustomSpeed":73.5,"minAccCustom":91.5,"minBurstCustomSpeed":83.5}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    for (target, text) in [(PracticeThresholdCommandTarget.minimumWpmCustom, "73.5"),
      (.minimumAccuracyCustom, "91.5"), (.minimumWordBurst(.fixed), ""), (.minimumWordBurst(.flex), "")] {
      let presentation = try XCTUnwrap(WebsiteThresholdCommandPresentation(publication: publication, target: target))
      XCTAssertEqual(presentation.id, publication.applicationID)
      XCTAssertEqual(presentation.unit, .cpm); XCTAssertEqual(presentation.initialText, text)
      for (width, dark) in [(460.0, false), (640.0, true)] {
        var calls = 0
        let view = WebsiteThresholdCommandView(presentation: presentation, canApply: true, apply: { _ in
          calls += 1; return .init(publicationID: UUID(), acceptedSetters: 0, rejectedKeys: [])
        }).frame(width: width, height: 340).background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 340),
          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/typebar-threshold-command-\(text.isEmpty ? "burst" : text)-\(Int(width)).png"))
        XCTAssertGreaterThan(png.count, 1000); XCTAssertFalse(window.isVisible); XCTAssertEqual(calls, 0)
      }
    }
    XCTAssertNil(WebsiteThresholdCommandPresentation(publication: publication, target: .minimumWpmOff))
  }

  func testThresholdCommandNonfiniteRepresentationFailureRetainsTheAcceptedBurstMode() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"minBurstCustomSpeed":83.5}"#, systemIsDark: false)
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    do {
      _ = try f.workflow.runThresholdCommand(.minimumWordBurst(.flex), input: String(repeating: "9", count: 400), replacing: id)
      XCTFail("Native finite domain must not silently turn infinity into zero")
    } catch WebsiteThresholdCommandError.partiallySaved {}
    let rules = try XCTUnwrap(f.page.state.session.configuration.rules.thresholdSource).configuration
    XCTAssertEqual(rules.minimumWordBurstMode, .flex); XCTAssertEqual(rules.minimumWordBurstCustomValue, 83.5)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }
  func testThresholdCommandKeepsBurstModeWhenItsValueSetterIsRefused() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"typingSpeedUnit":"cpm","minBurstCustomSpeed":83.5}"#, systemIsDark: false)
    var active = f.page.state
    active.session.insertBatch(String(active.session.prompt.prefix(1))); f.page.replace(active)
    let before = f.page.state.session
    let first = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let partial = try f.workflow.runThresholdCommand(.minimumWordBurst(.fixed), input: "-", replacing: first)
    XCTAssertEqual(partial.acceptedSetters, 1); XCTAssertEqual(partial.rejectedKeys, ["minBurstCustomSpeed"])
    var rules = try XCTUnwrap(f.page.state.session.configuration.rules.thresholdSource).configuration
    XCTAssertEqual(rules.minimumWordBurstMode, .fixed); XCTAssertEqual(rules.minimumWordBurstCustomValue, 83.5)
    let complete = try f.workflow.runThresholdCommand(.minimumWordBurst(.flex), input: "73.5tail", replacing: partial.publicationID)
    XCTAssertEqual(complete.acceptedSetters, 2); XCTAssertTrue(complete.rejectedKeys.isEmpty)
    rules = try XCTUnwrap(f.page.state.session.configuration.rules.thresholdSource).configuration
    XCTAssertEqual(rules.minimumWordBurstMode, .flex); XCTAssertEqual(rules.minimumWordBurstCustomValue, 14.6)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.typed, before.typed); XCTAssertEqual(f.page.state.session.prompt, before.prompt)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0); XCTAssertEqual(f.settings.snapshot, legacy)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing saved command") }
    XCTAssertEqual(saved["minBurst"], .string("flex")); XCTAssertEqual(saved["minBurstCustomSpeed"], .number(14.6))
    XCTAssertThrowsError(try f.workflow.runThresholdCommand(.minimumWpmOff, input: "", replacing: first))
  }

  func testThresholdCommandNoQuitRunsBothRefusedSettersAndEmptyBurstDoesNothing() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state
    active.session.insertBatch(String(active.session.prompt.prefix(1))); f.page.replace(active)
    let before = f.page.state.session.generationState
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let count = f.account.localNotices.history.count
    let empty = try f.workflow.runThresholdCommand(.minimumWordBurst(.fixed), input: "", replacing: id)
    XCTAssertEqual(empty.acceptedSetters, 0); XCTAssertTrue(empty.rejectedKeys.isEmpty)
    let refused = try f.workflow.runThresholdCommand(.minimumWordBurst(.fixed), input: " ", replacing: id)
    XCTAssertEqual(refused.rejectedKeys, ["minBurst", "minBurstCustomSpeed"])
    XCTAssertEqual(f.account.localNotices.history.count - count, 2)
    XCTAssertTrue(f.account.localNotices.active.allSatisfy(\.important))
    XCTAssertThrowsError(try f.workflow.runThresholdCommand(.minimumWpmCustom, input: "-1", replacing: id))
    XCTAssertEqual(f.account.localNotices.history.count - count, 2, "Prevalidation failure must not execute No Quit setters")
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
  }

  func testThresholdCommandSecondStepCannotAdoptACompetingRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    var writes = 0
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated {
        writes += 1
        do {
          guard case .committed = try register.commit(other, replacing: XCTUnwrap(register.read().revision)) else {
            return XCTFail("Cannot create competing record after mode save")
          }
        } catch { XCTFail("Competing writer failed: \(error)") }
      }
    }
    do {
      _ = try f.workflow.runThresholdCommand(.minimumWordBurst(.fixed), input: "50", replacing: id)
      XCTFail("Second command step overwrote a competing record")
    } catch WebsiteThresholdCommandError.partiallySaved {}
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime["minBurst"], .string("fixed"))
    guard case .available(let saved) = try register.read().state else { return XCTFail("Competing record lost") }
    XCTAssertEqual(saved["words"], .number(7)); XCTAssertEqual(saved["minBurst"], .string("off"))
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testThresholdCommandEmptySpeedUsesProfileUnitAndOffRetainsItsMemory() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"typingSpeedUnit":"cps"}"#, systemIsDark: false)
    var id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let submitted = try f.workflow.runThresholdCommand(.minimumWpmCustom, input: "1.7", replacing: id)
    let expected = 1.7 / (5.0 / 60.0)
    XCTAssertEqual(f.page.state.session.configuration.rules.minimumWpm, expected)
    id = submitted.publicationID
    let off = try f.workflow.runThresholdCommand(.minimumWpmOff, input: "", replacing: id)
    XCTAssertEqual(f.page.state.session.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, expected)
    let zero = try f.workflow.runThresholdCommand(.minimumWpmCustom, input: "", replacing: off.publicationID)
    XCTAssertEqual(zero.acceptedSetters, 1)
    XCTAssertEqual(f.page.state.session.configuration.rules.thresholdSource?.configuration.minimumWpmMode, .custom)
    XCTAssertEqual(f.page.state.session.configuration.rules.minimumWpm, 0)
  }
  func testThresholdEditRetainsCurrentQuoteAndItsSamplingQueueWithoutReadingAgain() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "one", title: "Owned", text: "ab cd", language: .english, length: .short),
          .init(id: "two", title: "Owned", text: "ef gh", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    let before = f.page.state.session.generationState
    let quote = f.page.state.practice?.quote?.id
    var expected = try XCTUnwrap(f.page.state.practice?.quoteSampler)
    var expectedBounds: [Int] = []
    let expectedNext = try expected.next(randomIndex: { expectedBounds.append($0); return 0 })
    try await workflow.editAndBegin(.threshold(.burstMode(.fixed)),
      replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(reads, 1); XCTAssertEqual(f.page.state.practice?.quote?.id, quote)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.attempt)
    var actual = try XCTUnwrap(f.page.state.practice?.quoteSampler)
    var actualBounds: [Int] = []
    XCTAssertEqual(try actual.next(randomIndex: { actualBounds.append($0); return 0 }), expectedNext)
    XCTAssertEqual(actualBounds, expectedBounds)
  }
  func testAllThresholdModesAndMemoriesSaveWithoutRestartAndOffRetainsValues() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"minWpm":"off","minWpmCustomSpeed":73.5,"minAcc":"off","minAccCustom":91.5,"minBurst":"off","minBurstCustomSpeed":83.5}"#,
      systemIsDark: false)
    let attempt = f.page.state.session.automaticInputAttemptID
    let controller = try XCTUnwrap(f.page.restartController)
    let edits: [WebsiteConfigThresholdEdit] = [.speedMode(.custom), .speedMode(.off), .speedValue(0),
      .accuracyValue(0), .accuracyMode(.off), .burstValue(99.5), .burstMode(.flex), .burstValue(0), .burstMode(.fixed), .burstMode(.off)]
    for edit in edits {
      let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
      try await f.workflow.editAndBegin(.threshold(edit), replacing: id, systemIsDark: false)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertTrue(f.page.restartController === controller)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
      let configuration = try XCTUnwrap(f.page.state.session.configuration.rules.thresholdSource).configuration
      if edit == .speedMode(.off) { XCTAssertEqual(configuration.minimumWpmCustomValue, 73.5) }
      if edit == .burstValue(99.5) { XCTAssertEqual(configuration.minimumWordBurstMode, .off) }
      if edit == .burstValue(0) { XCTAssertEqual(configuration.minimumWordBurstMode, .flex) }
      if edit == .burstMode(.fixed) { XCTAssertEqual(configuration.minimumWordBurstCustomValue, 0) }
    }
    let source = try XCTUnwrap(f.page.state.session.configuration.rules.thresholdSource).configuration
    XCTAssertEqual(source.minimumWpmMode, .custom); XCTAssertEqual(source.minimumWpmCustomValue, 0)
    XCTAssertEqual(source.minimumAccuracyMode, .off); XCTAssertEqual(source.minimumAccuracyCustomValue, 0)
    XCTAssertEqual(source.minimumWordBurstMode, .off); XCTAssertEqual(source.minimumWordBurstCustomValue, 0)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Threshold fields were not saved")
    }
    XCTAssertEqual(saved["minWpm"], .string("custom")); XCTAssertEqual(saved["minWpmCustomSpeed"], .number(0))
    XCTAssertEqual(saved["minBurst"], .string("off")); XCTAssertEqual(saved["minBurstCustomSpeed"], .number(0))
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testNoQuitRejectsEveryThresholdFieldWithoutChangingAttemptOrDisk() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state
    active.session.insertBatch(String(active.session.prompt.prefix(1))); f.page.replace(active)
    let generation = f.page.state.session.generationState
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let count = f.account.localNotices.history.count
    for edit in [WebsiteConfigThresholdEdit.speedMode(.custom), .speedValue(20), .accuracyMode(.custom),
      .accuracyValue(90), .burstMode(.fixed), .burstValue(30)] {
      do {
        try await f.workflow.editAndBegin(.threshold(edit), replacing: publication, systemIsDark: false)
        XCTFail("No Quit accepted \(edit.key)")
      } catch WebsiteConfigNativeDraftError.rejectedEdit {}
      XCTAssertEqual(f.page.state.session.generationState, generation)
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    }
    XCTAssertEqual(f.account.localNotices.history.count - count, 6)
    XCTAssertTrue(try XCTUnwrap(f.account.localNotices.active.last).important)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testInvalidThresholdValuesNeverRestartOrSave() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    let generation = f.page.state.session.generationState
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    for edit in [WebsiteConfigThresholdEdit.speedValue(-1), .speedValue(.infinity), .speedValue(.nan),
      .accuracyValue(101), .burstValue(-1)] {
      do { try await f.workflow.editAndBegin(.threshold(edit), replacing: publication, systemIsDark: false); XCTFail("Invalid threshold accepted") }
      catch {}
      XCTAssertEqual(f.page.state.session.generationState, generation)
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    }
  }

  func testFinishedOnlineResultKeepsItsRulesButExplicitRepeatUsesNewThresholdSelection() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { source, _, _, _ in
        reads += 1
        return .init(source: source, initial: .init(text: "ab cd", noSpaceBoundarySource: nil), continuation: nil)
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":2,"funbox":["wikipedia"]}"#, systemIsDark: false)
    var complete = f.page.state
    complete.session.insertBatch(complete.session.prompt + " "); f.page.replace(complete)
    XCTAssertEqual(f.page.state.session.outcome, .completed)
    let original = f.page.state.session
    try await workflow.editAndBegin(.threshold(.accuracyValue(0)),
      replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.generationState, original.generationState)
    let repeated = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(repeated); XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.session.prompt, original.prompt)
    XCTAssertEqual(f.page.state.session.configuration.rules.thresholdSource?.configuration.minimumAccuracyMode, .custom)
    XCTAssertEqual(f.page.state.session.configuration.rules.thresholdSource?.configuration.minimumAccuracyCustomValue, 0)
  }
  func testThresholdSetterKeepsActiveAttemptInputPromptAndLedger() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":10,"minWpm":"off","minWpmCustomSpeed":73.5}"#,
      systemIsDark: false)
    var running = f.page.state
    running.session.insertBatch(String(running.session.prompt.prefix(1)))
    f.page.replace(running)
    let before = f.page.state.session
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    try await f.workflow.editAndBegin(.threshold(.speedValue(0)), replacing: publication, systemIsDark: false)
    let after = f.page.state.session
    XCTAssertEqual(after.automaticInputAttemptID, before.automaticInputAttemptID)
    XCTAssertEqual(after.typed, before.typed)
    XCTAssertEqual(after.prompt, before.prompt)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(after.configuration.rules.thresholdSource?.configuration.minimumWpmMode, .custom)
    XCTAssertEqual(after.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, 0)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testRetiredShortSectionDoesNotStartAnotherRequestForEitherOnlineSource() async throws {
    let cases = ["page", "record", "window", "cancel"].flatMap { retirement in
      ["poetry", "wikipedia"].map { (retirement, $0) }
    }
    for (retirement, name) in cases {
      let f = try Fixture(); defer { f.close() }
      var reads = 0
      var reply: CheckedContinuation<LivePracticeContent?, Never>?
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadExternal: { source, configuration, allLines, check in
          try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
            showAllLines: allLines, checkCurrent: check) { _, _ in
            reads += 1
            if reads == 1 { return await withCheckedContinuation { reply = $0 } }
            return .init(source: source, title: "Unwanted follow-up", byline: nil,
              tokens: ["cd", "ef", "gh"], separator: " ")
          }
        })
      defer { workflow.stop(); reply?.resume(returning: nil) }
      let old = Task { try await workflow.apply(json: "{\"mode\":\"words\",\"words\":4,\"funbox\":[\"\(name)\"]}",
        systemIsDark: false) }
      let deadline = ContinuousClock.now.advanced(by: .seconds(3))
      while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
      guard let delayed = reply else { old.cancel(); return XCTFail("Initial source request did not suspend") }
      reply = nil
      let register = WebsiteConfigFileRegister(directory: f.directory)
      let replacement = #"{"mode":"words","words":7,"funbox":["rot13"]}"#
      switch retirement {
      case "page": try await f.workflow.apply(json: replacement, systemIsDark: false)
      case "record":
        let draft = try WebsiteConfigNativeProfile.prepareDraft(replacement, pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
          delayed.resume(returning: nil); return XCTFail("Competing record not saved")
        }
      case "window": f.window.revision = UUID()
      default: workflow.cancel()
      }
      let before = f.page.state.session.generationState
      let revision = try register.read().revision
      delayed.resume(returning: .init(source: name == "poetry" ? .poetry : .encyclopedia,
        title: "Retired short section", byline: nil, tokens: ["ab"], separator: " "))
      do { _ = try await old.value; XCTFail("Retired initialization delivered") }
      catch is CancellationError { XCTAssertEqual(retirement, "cancel") }
      catch let error as WebsiteConfigSavedPreparationError {
        XCTAssertTrue(retirement == "record" || retirement == "window")
        XCTAssertEqual(error.underlying as? WebsiteConfigCommitCoordinatorError, .stale)
      }
      catch {
        XCTAssertEqual(retirement, "page")
        XCTAssertEqual(error as? WebsiteConfigCommitCoordinatorError, .stale)
      }
      XCTAssertEqual(reads, 1, "\(retirement): a retired short section must not issue another \(name) request")
      XCTAssertEqual(f.page.state.session.generationState, before)
      XCTAssertEqual(try register.read().revision, revision)
    }
  }
  func testPublishedPoetryRecoveryRequiresFailureAndDoesNotRestoreMemorySelection() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { source, configuration, allLines, check in
        try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
          showAllLines: allLines, checkCurrent: check) { _, _ in
          .init(source: source, title: "Owned", byline: nil, tokens: Array(repeating: "ab", count: 100), separator: " ")
        }
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":201,"showAllLines":false,"funbox":["poetry","memory"]}"#,
      systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let revision = try register.read().revision
    do {
      try await workflow.recoverFailedPoetry(replacing: publication, systemIsDark: false)
      XCTFail("An automatic correction must not remove a healthy source")
    } catch { XCTAssertEqual(error as? WebsiteConfigCommitCoordinatorError, .sessionNotReady) }
    XCTAssertEqual(try register.read().revision, revision)
    var failed = f.page.state
    failed.session.insertBatch("ab "); failed.session.failLiveContentFetch(); f.page.replace(failed)
    XCTAssertEqual(f.page.state.session.outcome, .failed)
    try await workflow.recoverFailedPoetry(replacing: publication, systemIsDark: false)
    let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertEqual(draft.projection.runtime["funbox"], .array([.string("memory")]))
    XCTAssertTrue(draft.funboxMemory.entries.contains(.init(key: "showAllLines", value: .bool(false))))
    guard case .available(let saved) = try register.read().state else { return XCTFail("Correction not saved") }
    XCTAssertEqual(saved["showAllLines"], .bool(true))
    XCTAssertEqual(saved["funbox"], .array([.string("memory")]))
    XCTAssertNil(f.page.state.practice?.external)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  func testLatePoetryFailureCannotCorrectACompetingAcceptedProfile() async throws {
    let f = try Fixture(); defer { f.close() }
    var reply: CheckedContinuation<LivePracticeContent?, Never>?
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { source, configuration, allLines, check in
        try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
          showAllLines: allLines, checkCurrent: check) { _, _ in await withCheckedContinuation { reply = $0 } }
      })
    defer { workflow.stop(); reply?.resume(returning: nil) }
    let pending = Task { try await workflow.apply(json: #"{"mode":"words","words":4,"funbox":["poetry"]}"#,
      systemIsDark: false) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
    guard let late = reply else { pending.cancel(); return XCTFail("External read did not suspend") }
    reply = nil
    try await f.workflow.apply(json: #"{"mode":"words","words":7,"funbox":["rot13"]}"#, systemIsDark: false)
    let generation = f.page.state.session.generationState
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    late.resume(returning: nil)
    do { _ = try await pending.value; XCTFail("Late failure corrected a newer profile") }
    catch { XCTAssertEqual(error as? WebsiteConfigCommitCoordinatorError, .stale) }
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 7)
  }
  func testPoetryFalseSavesOnlySourceRemovalAndPreservesActivatedMemorySettings() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { source, configuration, allLines, check in
        XCTAssertTrue(allLines, "The loader must see Memory's activated showAllLines")
        return try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
          showAllLines: allLines, checkCurrent: check) { _, _ in reads += 1; return nil }
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"showAllLines":false,"funbox":["poetry","memory"]}"#,
      systemIsDark: false)
    XCTAssertEqual(reads, 1)
    let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertEqual(draft.projection.runtime["funbox"], .array([.string("memory")]))
    XCTAssertEqual(draft.projection.runtime["showAllLines"], .bool(true))
    XCTAssertTrue(draft.funboxMemory.entries.contains(.init(key: "showAllLines", value: .bool(false))))
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Source removal was not saved")
    }
    XCTAssertEqual(saved["funbox"], .array([.string("memory")]))
    XCTAssertEqual(saved["showAllLines"], .bool(true), "Automatic toggle must not restore selection memory")
    XCTAssertNil(f.page.state.practice?.external)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testWikipediaFailureKeepsSavedSourceAndUsesBoundedRetryBeforeRecovery() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0, available = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { source, configuration, allLines, check in
        try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
          showAllLines: allLines, checkCurrent: check) { _, _ in
          reads += 1
          return available ? .init(source: source, title: "Recovered", byline: nil,
            tokens: ["ab", "cd", "ef", "gh"], separator: " ") : nil
        }
      })
    defer { workflow.stop() }
    do {
      try await workflow.apply(json: #"{"mode":"words","words":4,"funbox":["wikipedia"]}"#, systemIsDark: false)
      XCTFail("Failed source delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.generationFailed = error.underlying else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(reads, 3); XCTAssertNotNil(f.page.state.savedApplication)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let before = try register.read()
    guard case .available(let saved) = before.state else { return XCTFail("Accepted source lost") }
    XCTAssertEqual(saved["funbox"], .array([.string("wikipedia")]))
    available = true
    try await workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(reads, 4); XCTAssertEqual(f.page.state.session.prompt, "ab cd ef gh")
    XCTAssertEqual(try register.read().revision, before.revision)
    XCTAssertNil(f.page.state.savedApplication)
  }
  func testExternalProviderSurvivesImportNextAndExplicitRepetitionWithoutLegacyWrites() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadExternal: { source, config, allLines, _ in
        XCTAssertEqual(source, .encyclopedia); XCTAssertEqual(config.wordLimit, 4); XCTAssertTrue(allLines)
        reads += 1
        return .init(source: source, initial: .init(text: reads == 1 ? "ab cd ef gh" : "ij kl mn op",
          noSpaceBoundarySource: nil), continuation: nil, attribution: "Owned article \(reads)")
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"showAllLines":true,"funbox":["wikipedia"]}"#,
      systemIsDark: false)
    XCTAssertEqual(f.page.state.session.prompt, "ab cd ef gh")
    XCTAssertEqual(f.page.state.practice?.external?.attribution, "Owned article 1")
    let controller = try XCTUnwrap(f.page.restartController)
    let first = f.page.state.session.automaticInputAttemptID
    let repeated = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(repeated); XCTAssertEqual(reads, 1)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, first)
    XCTAssertEqual(f.page.state.session.prompt, "ab cd ef gh")
    let next = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(next); XCTAssertEqual(reads, 2)
    XCTAssertEqual(f.page.state.session.prompt, "ij kl mn op")
    XCTAssertEqual(f.settings.snapshot, legacy)
  }
  @MainActor private final class WeakWorkflow { weak var value: WebsiteConfigImportWorkflow? }
  func testCancelledColdRestorationKeepsUnchangedRecordAndCanRecoverWithNewWorkflow() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let stored = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"quote","quoteLength":[0]}"#,
      pointsPerRem: 16, context: .init())
    guard case .committed = try register.commit(stored, replacing: XCTUnwrap(register.read().revision)) else {
      return XCTFail("Cannot seed private cold record")
    }
    let revision = try register.read().revision
    let capture = try f.page.captureApplication(router: f.settings.preferenceConfigurationSaves)
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    let task = Task { try await workflow.apply(json: nil, systemIsDark: false) }
    try await gate.wait(); try assertPendingSavedImport(f)
    XCTAssertFalse(f.page.isCurrent(capture, router: f.settings.preferenceConfigurationSaves))
    XCTAssertEqual(try register.read().revision, revision)
    task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled cold load delivered") } catch is CancellationError {}
    XCTAssertEqual(try register.read().revision, revision); XCTAssertNil(f.page.state.practice)
    workflow.stop()
    let recovered = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        [.init(id: "owned", title: "Owned cold recovery", text: "ab cd", language: .english, length: .short)]
      })
    defer { recovered.stop() }
    try await recovered.apply(json: nil, systemIsDark: false)
    XCTAssertNil(f.page.state.savedApplication)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertEqual(try register.read().revision, revision)
  }
  func testColdRestorationSavesCorrectionBeforeFailedInitializationAndResumesWithoutRewriting() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let stored = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"quote","quoteLength":[-3],"theme":"dracula"}"#,
      pointsPerRem: 16, context: .init(authenticated: true))
    guard case .committed = try register.commit(stored, replacing: XCTUnwrap(register.read().revision)) else {
      return XCTFail("Cannot seed private cold record")
    }
    var failing = true, reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        guard case .available(let fields) = try register.read().state else { throw Failure.provider }
        XCTAssertEqual(fields["quoteLength"], .array([0,1,2,3].map { .number(Double($0)) }),
          "Cold initialization must save the actual automatic correction before reading")
        if failing { throw Failure.provider }
        return [.init(id: "owned", title: "Owned cold retry", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: nil, systemIsDark: false); XCTFail("Failed cold initialization delivered") }
    catch { XCTAssertTrue(error is WebsiteConfigSavedPreparationError) }
    XCTAssertEqual(reads, 3); try assertPendingSavedImport(f)
    let revision = try register.read().revision
    failing = false; try await workflow.apply(json: nil, systemIsDark: false)
    XCTAssertNil(f.page.state.savedApplication)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
  }
  private func assertPendingSavedImport(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Accepted import lost its saved record", file: file, line: line)
    }
    XCTAssertEqual(saved["mode"], .string("quote"), file: file, line: line)
    XCTAssertNotNil(f.page.state.savedApplication, file: file, line: line)
    XCTAssertTrue(f.page.ownsConfigurationSelection, file: file, line: line)
    XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID), file: file, line: line)
  }

  func testAcceptanceOnPublishedPageRetiresItsCaptureAndControllerWithoutChangingTheOldAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let before = f.page.state.session.generationState, old = try f.page.captureGeneration(router: f.settings.preferenceConfigurationSaves)
    let controller = try XCTUnwrap(f.page.restartController)
    let task = Task { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false) }
    try await gate.wait()
    try assertPendingSavedImport(f)
    XCTAssertFalse(f.page.isCurrent(old, router: f.settings.preferenceConfigurationSaves))
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old.publication.applicationID)
    XCTAssertNil(f.page.restartController); XCTAssertFalse(controller.request())
    task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled replacement delivered") } catch is CancellationError {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testObserverRetirementAtAcceptanceReportsSavedWithoutInstallingAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let attempt = f.page.state.session.automaticInputAttemptID
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.page.detach() }
    }
    do { try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false); XCTFail("Retired acceptance delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertEqual(error.underlying as? WebsiteConfigCommitCoordinatorError, .stale)
      XCTAssertTrue(error.configurationWasSaved)
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNil(f.page.state.practice)
    XCTAssertNotNil(f.page.state.savedApplication)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Accepted record lost after observer retirement")
    }
    XCTAssertEqual(saved["words"], .number(4))
  }

  func testCancelledSavedApplicationCanBeColdRecoveredByNewWorkflow() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    let task = Task { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"theme":"dracula"}"#, systemIsDark: false) }
    try await gate.wait()
    XCTAssertNotNil(f.page.state.savedApplication)
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled initializer delivered") } catch is CancellationError {}
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertNotNil(f.page.state.savedApplication)
    workflow.stop()
    let recovered = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        [.init(id: "owned", title: "Owned cold recovery", text: "ab cd", language: .english, length: .short)]
      })
    defer { recovered.stop() }
    try await recovered.apply(json: nil, systemIsDark: false)
    XCTAssertNil(f.page.state.savedApplication)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(try register.read().revision, revision)
  }

  func testSavedApplicationCannotOverwriteCompetingRecordAndExplicitRestoreReadsTheCompetitor() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7,"theme":"nord"}"#,
      pointsPerRem: 16, context: .init())
    var competed = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if !competed {
          competed = true
          guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
            throw Failure.provider
          }
        }
        return [.init(id: "owned", title: "Owned stale reader", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    let attempt = f.page.state.session.automaticInputAttemptID
    do { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false); XCTFail("Competitor overwritten") }
    catch {}
    XCTAssertTrue(competed); XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    let revision = try register.read().revision
    try await workflow.apply(json: nil, systemIsDark: false)
    XCTAssertNil(f.page.state.savedApplication)
    XCTAssertEqual(f.page.state.session.configuration.mode, .words)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 7)
    XCTAssertEqual(try register.read().revision, revision)
  }

  func testReturningToTypebarDuringSavedApplicationRetiresLateInitializerWithoutDeletingRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    let task = Task { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false) }
    try await gate.wait()
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    let permit = try f.page.beginLegacyReturn()
    var legacy = f.page.state
    legacy.session = TestSessionFactory.make(configuration: .words(3))
    f.page.replace(legacy); try f.page.finishLegacyReturn(permit)
    let attempt = f.page.state.session.automaticInputAttemptID
    gate.resolve()
    do { _ = try await task.value; XCTFail("Retired initializer installed") } catch {}
    XCTAssertNil(f.page.state.savedApplication)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertFalse(f.page.ownsConfigurationSelection)
    XCTAssertTrue(f.page.acceptsInput(for: attempt))
    XCTAssertEqual(try register.read().revision, revision)
  }

  func testSavedApplicationPersistsAutomaticQuoteCorrectionBeforeFailureAndDoesNotReplayItOnResume() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var failing = true, revisions: [WebsiteConfigFileRegister.Revision?] = []
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        revisions.append(try register.read().revision)
        guard case .available(let saved) = try register.read().state else { throw Failure.provider }
        XCTAssertEqual(saved["quoteLength"], .array([0,1,2,3].map { .number(Double($0)) }))
        if failing { throw Failure.provider }
        return [.init(id: "owned", title: "Owned correction", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[-3]}"#, systemIsDark: false); XCTFail("Failing reader delivered") }
    catch { XCTAssertTrue(error is WebsiteConfigSavedPreparationError) }
    XCTAssertEqual(revisions.count, 3); XCTAssertTrue(revisions.allSatisfy { $0 == revisions.first! })
    let revision = try register.read().revision
    failing = false; try await workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertNil(f.page.state.savedApplication)
  }

  func testFullImportSavesBeforeInitializationAndRecoversItsSavedProfileAfterFailure() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var failing = true, reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        guard case .available(let saved) = try register.read().state else { throw Failure.provider }
        XCTAssertEqual(saved["mode"], .string("quote"), "Import must be saved before the text reader runs")
        if failing { throw Failure.provider }
        return [.init(id: "owned", title: "Owned recovery", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    let originalAttempt = f.page.state.session.automaticInputAttemptID
    do {
      try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"theme":"dracula"}"#, systemIsDark: false)
      XCTFail("Failing initializer delivered")
    } catch { XCTAssertTrue(error is WebsiteConfigSavedPreparationError, "Saved import must report its durable state: \(error)") }
    XCTAssertEqual(reads, 3)
    XCTAssertFalse(f.page.acceptsInput(for: originalAttempt))
    guard case .available(let saved) = try register.read().state else { return XCTFail("Accepted import disappeared") }
    XCTAssertEqual(saved["mode"], .string("quote")); XCTAssertEqual(saved["theme"], .string("dracula"))
    let revision = try register.read().revision
    failing = false
    try await workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(try register.read().revision, revision, "Resume must not repeat the accepted import write")
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
  }

  func testLayoutfluidCommandSnapshotSavesThroughCorrectLifecycleAndRejectsOldWindow() async throws {
    for enabled in [false, true] {
      for noQuit in [false, true] {
        let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
        let names = (enabled ? ["layoutfluid"] : []) + (noQuit ? ["no_quit"] : [])
        let jsonNames = String(decoding: try JSONEncoder().encode(names), as: UTF8.self)
        try await f.workflow.apply(json: "{\"mode\":\"words\",\"words\":4,\"funbox\":\(jsonNames)}", systemIsDark: false)
        var active = f.page.state; active.session.insertBatch("x"); f.page.replace(active)
        let before = active.session.generationState
        let opened = WebsiteSequenceCommandPresentation(publication: try XCTUnwrap(f.page.state.presentation).publication,
          kind: .layoutFluid)
        let form = WebsiteConfigPracticeEditForm(draft: opened.draft)
        XCTAssertEqual(opened.kind, .layoutFluid)
        XCTAssertEqual(form.layoutFluidLayouts, "qwerty dvorak colemak")
        form.layoutFluidLayouts = "colemak qwerty"
        let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
        opened.kind.submit(form) { edit in
          try await f.workflow.editAndBegin(edit, replacing: opened.id, systemIsDark: false)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(form.isWorking)
        let current = try XCTUnwrap(f.page.state.presentation).publication
        if noQuit {
          XCTAssertEqual(try register.read().revision, revision)
          XCTAssertEqual(current.applicationID, opened.id)
          XCTAssertEqual(f.page.state.session.generationState, before)
          XCTAssertTrue(form.message?.contains("设置未修改") == true)
          XCTAssertEqual(f.account.localNotices.history.count, 1)
        } else {
          XCTAssertNotEqual(try register.read().revision, revision)
          XCTAssertNotEqual(current.applicationID, opened.id)
          XCTAssertEqual(current.draft.generators.layoutFluidLayouts.compactMap(OfficialLayoutCommandCatalog.name), ["colemak", "qwerty"])
          XCTAssertEqual(f.page.state.session.automaticInputAttemptID != active.session.automaticInputAttemptID, enabled)
          if !enabled { XCTAssertEqual(f.page.state.session.generationState, before) }
          let saved = try register.read().revision
          do {
            try await f.workflow.editAndBegin(.layoutFluidLayouts(["dvorak", "qwerty"]), replacing: opened.id, systemIsDark: false)
            XCTFail("Old command edited replacement")
          } catch WebsiteConfigImportWorkflowError.conflict {}
          XCTAssertEqual(try register.read().revision, saved)
        }
      }
    }
  }

  func testLayoutfluidSequenceWorkflowMatchesPinnedCommandAndSubscription() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct FixtureCase: Decodable {
      let raw: String, converted: [String], saved: [String], page: String
      let canSubmit, enabled, active, noQuit, accepted: Bool
      let restarts: Int
    }
    struct Output: Decodable { let fixtures: [FixtureCase] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-layoutfluid-list-command.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 144)
    for fixture in fixtures where fixture.page == "test" && fixture.canSubmit {
      let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
      let names = (fixture.enabled ? ["layoutfluid"] : []) + (fixture.noQuit ? ["no_quit"] : [])
      let jsonNames = String(decoding: try JSONEncoder().encode(names), as: UTF8.self)
      try await f.workflow.apply(json: "{\"mode\":\"words\",\"words\":4,\"funbox\":\(jsonNames)}", systemIsDark: false)
      if fixture.active {
        var active = f.page.state; active.session.insertBatch("x"); f.page.replace(active)
        XCTAssertTrue(f.page.state.session.hasStarted)
      }
      let old = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      let before = f.page.state.session.generationState
      let register = WebsiteConfigFileRegister(directory: f.directory), disk = try register.read().revision
      do {
        try await f.workflow.editAndBegin(.layoutFluidLayouts(fixture.converted), replacing: old.applicationID, systemIsDark: false)
        XCTAssertTrue(fixture.accepted, fixture.raw)
      } catch WebsiteConfigNativeDraftError.rejectedEdit { XCTAssertFalse(fixture.accepted, fixture.raw) }
      let current = try XCTUnwrap(f.page.state.presentation).publication
      XCTAssertEqual(current.draft.generators.layoutFluidLayouts.compactMap(OfficialLayoutCommandCatalog.name), fixture.saved)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID != attempt, fixture.restarts == 1, fixture.raw)
      XCTAssertEqual(try register.read().revision != disk, fixture.accepted, fixture.raw)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, fixture.active ? fixture.restarts : 0)
      XCTAssertNil(f.page.state.configurationDeparture)
      if fixture.restarts == 0 { XCTAssertEqual(f.page.state.session.generationState, before) }
      if fixture.accepted && fixture.enabled {
        XCTAssertEqual(current.draft.projection.runtime["layout"], fixture.saved.first.map(WebsiteConfigValue.string))
        XCTAssertEqual(current.draft.projection.runtime["keymapLayout"], fixture.saved.first.map(WebsiteConfigValue.string))
      }
      if fixture.active && fixture.noQuit {
        XCTAssertEqual(f.account.localNotices.history.count, 1)
        XCTAssertTrue(try XCTUnwrap(f.account.localNotices.active.first).important)
      }
    }
  }

  func testInactiveLayoutfluidSequenceSavesWithoutRestartingCurrentAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"theme":"dracula"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication
    let before = f.page.state.session, controller = f.page.restartController
    let message = try await f.workflow.editAndBegin(.layoutFluidLayouts(["colemak", "qwerty", "colemak"]),
      replacing: old.applicationID, systemIsDark: false)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertEqual(current.draft.generators.layoutFluidLayouts.compactMap(OfficialLayoutCommandCatalog.name), ["colemak", "qwerty"])
    XCTAssertNotEqual(current.applicationID, old.applicationID)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.generationState, before.generationState)
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertTrue(f.page.restartController === controller)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertTrue(message.contains("当前练习继续"))
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Missing saved sequence")
    }
    XCTAssertEqual(saved["customLayoutfluid"], .array([.string("colemak"), .string("qwerty")]))
    let register = WebsiteConfigFileRegister(directory: f.directory), firstRevision = try register.read().revision
    try await f.workflow.editAndBegin(.layoutFluidLayouts(["colemak", "qwerty"]),
      replacing: current.applicationID, systemIsDark: false)
    let sameValue = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertNotEqual(try register.read().revision, firstRevision, "A same-value source setter still saves")
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
    let form = WebsiteConfigPracticeEditForm(draft: sameValue.draft)
    form.layoutFluidLayouts = "qwerty qwerty"
    let revision = try register.read().revision
    form.startLayoutFluidLayouts { edit in
      try await f.workflow.editAndBegin(edit, replacing: sameValue.applicationID, systemIsDark: false)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking); XCTAssertTrue(form.message?.contains("设置未修改") == true)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.session.generationState, before.generationState)
  }

  func testPolyglotCommandSnapshotUsesPublishedDraftAndCannotEditReplacement() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"customPolyglot":["german","spanish"]}"#, systemIsDark: false)
    let opened = WebsiteSequenceCommandPresentation(publication: try XCTUnwrap(f.page.state.presentation).publication)
    let form = WebsiteConfigPracticeEditForm(draft: opened.draft)
    XCTAssertEqual(form.polyglotLanguages, "german spanish")
    form.polyglotLanguages = "french english"
    form.startPolyglotLanguages { edit in
      try await f.workflow.editAndBegin(edit, replacing: opened.id, systemIsDark: false)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking); XCTAssertNotNil(form.message)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertNotEqual(opened.id, current.applicationID)
    XCTAssertEqual(current.draft.generators.polyglotLanguages, [.french, .english])
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    do {
      try await f.workflow.editAndBegin(.polyglotLanguages(["german", "english"]), replacing: opened.id, systemIsDark: false)
      XCTFail("A command opened on the old publication edited its replacement")
    } catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
  }

  func testFuturePolyglotSaveRepeatsOldHistoryThenContinuesFromNewLanguages() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"time","time":1,"funbox":["polyglot","no_quit"],"customPolyglot":["english","german"]}"#, systemIsDark: false)
    let zero = Date.now
    var active = f.page.state
    let first = try XCTUnwrap(active.session.prompt.split(separator: " ").first)
    active.session.insertBatch(String(first) + " ", at: zero)
    f.page.replace(active)
    let history = try XCTUnwrap(active.session.generatedWordReplayHistory)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    try await f.workflow.editAndBegin(.polyglotLanguages(["spanish", "french"]),
      replacing: publication.applicationID, systemIsDark: false)
    let controller = try XCTUnwrap(f.page.restartController)
    let blocked = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertFalse(blocked, "Saving a future selection must not bypass active No Quit")
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, active.session.automaticInputAttemptID)
    // Published sessions own a monotonic system clock. Wait for this one-second
    // deadline instead of pretending calendar-date arguments advance that clock.
    XCTAssertEqual(f.page.state.session.configuration.duration, 1)
    try await Task.sleep(for: .milliseconds(1_100))
    var finished = f.page.state
    _ = finished.session.tick()
    XCTAssertTrue(finished.session.isFinished); f.page.replace(finished)
    let advanced = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(advanced)
    XCTAssertTrue(f.page.state.practice?.repetition.repeatsWordset == true)
    XCTAssertEqual(f.page.state.session.configuration.mixedLanguageComponents, [.spanish, .french])
    var repeated = f.page.state.session
    let replayStart = Date.now
    // Consume through the opening and prefetched history, using the actual
    // session continuation rather than constructing a replacement generator.
    for _ in 0..<(history.count + 100) {
      if (repeated.generatedWordReplayHistory?.count ?? 0) > history.count { break }
      let remaining = repeated.prompt.dropFirst(repeated.typed.count)
      guard let separator = remaining.firstIndex(of: " ") else { return XCTFail("No continuation word") }
      repeated.insertBatch(String(remaining[...separator]), at: replayStart)
    }
    let replayed = try XCTUnwrap(repeated.generatedWordReplayHistory)
    XCTAssertGreaterThan(replayed.count, history.count)
    for index in 0..<history.count {
      XCTAssertEqual(replayed.word(at: index)?.source, history.word(at: index)?.source)
      XCTAssertEqual(replayed.word(at: index)?.target, history.word(at: index)?.target)
    }
    let candidates = NativePolyglotCandidates(configuration: repeated.configuration, nextShuffleIndex: { $0 - 1 })
    let currentWords = Set(candidates.lexicon.materialized())
    for index in history.count..<replayed.count {
      XCTAssertTrue(currentWords.contains(try XCTUnwrap(replayed.word(at: index)?.source)),
        "History exhaustion must sample the saved language list")
    }
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testPolyglotLanguageListSavesDuringActiveNoQuitWithoutChangingItsAttempt() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"theme":"dracula","funbox":["polyglot","no_quit"],"customPolyglot":["english","german"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let before = f.page.state.session, old = try XCTUnwrap(f.page.state.presentation).publication
    let controller = try XCTUnwrap(f.page.restartController)
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    let message = try await f.workflow.editAndBegin(.polyglotLanguages(["spanish", "french"]),
      replacing: old.applicationID, systemIsDark: false)
    XCTAssertTrue(message.contains("已保存")); XCTAssertTrue(message.contains("当前练习"))
    let current = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertNotEqual(current.applicationID, old.applicationID)
    XCTAssertEqual(current.draft.generators.polyglotLanguages, [.spanish, .french])
    XCTAssertEqual(f.page.state.session.generationState, before.generationState)
    XCTAssertEqual(f.page.state.session.configuration, before.configuration)
    XCTAssertEqual(f.page.state.session.prompt, before.prompt)
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertTrue(f.page.restartController === controller)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertTrue(try XCTUnwrap(f.account.localNotices.active.first).important)
    XCTAssertNotEqual(try register.read().revision, revision)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing saved selection") }
    XCTAssertEqual(saved["customPolyglot"], .array([.string("spanish"), .string("french")]))
    XCTAssertEqual(saved["theme"], .string("dracula"))
    let savedRevision = try register.read().revision
    do { try await f.workflow.editAndBegin(.polyglotLanguages(["english", "german"]), replacing: old.applicationID, systemIsDark: false); XCTFail("Old editor applied") }
    catch {}
    do { try await f.workflow.editAndBegin(.words(8), replacing: current.applicationID, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch {}
    XCTAssertEqual(try register.read().revision, savedRevision)
    var finished = f.page.state
    finished.session.insertBatch(String(finished.session.prompt.dropFirst(finished.session.typed.count)))
    XCTAssertTrue(finished.session.isFinished); f.page.replace(finished)
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(advanced)
    XCTAssertEqual(f.page.state.session.configuration.mixedLanguageComponents, [.spanish, .french])
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testRejectedPolyglotListUnderNoQuitKeepsRevisionAndPostsImportantNotice() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    do { try await f.workflow.editAndBegin(.polyglotLanguages(["english", "english"]), replacing: old.applicationID, systemIsDark: false); XCTFail("Rejected list saved or restarted") }
    catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old.applicationID)
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertTrue(try XCTUnwrap(f.account.localNotices.active.first).important)
  }

  func testPolyglotLanguageListEditsUseSetterOrderingAndRestartEvenWhenInactive() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"theme":"dracula"}"#, systemIsDark: false)
    let old = try XCTUnwrap(f.page.state.presentation).publication
    try await f.workflow.editAndBegin(.polyglotLanguages(["german", "english", "german"]), replacing: old.applicationID, systemIsDark: false)
    let current = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertNotEqual(current.session?.automaticInputAttemptID, old.session?.automaticInputAttemptID)
    XCTAssertEqual(current.draft.generators.polyglotLanguages, [.german, .english])
    XCTAssertFalse(current.draft.generators.requestsPolyglot)
    XCTAssertEqual(current.draft.themes.theme, .dracula)
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let attempt = f.page.state.session.automaticInputAttemptID
    let message = try await f.workflow.editAndBegin(.polyglotLanguages(["english", "english"]), replacing: current.applicationID, systemIsDark: false)
    XCTAssertTrue(message.contains("设置未修改"))
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
  }

  func testFuturePolyglotSaveAfterOrdinaryRoundKeepsCoherentSeedAndCurrentAppearance() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"],"customPolyglot":["english","german"]}"#, systemIsDark: false)
    var finished = f.page.state; finished.session.insertBatch(finished.session.prompt)
    XCTAssertTrue(finished.session.isFinished); f.page.replace(finished)
    let advanced = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID())
    XCTAssertTrue(advanced)
    var active = f.page.state; active.session.insertBatch("x"); f.page.replace(active)
    let previous = try XCTUnwrap(f.page.state.presentation)
    _ = previous.updateSystemAppearance(isDark: true)
    let appearance = previous.appearance, attempt = active.session.automaticInputAttemptID
    try await f.workflow.editAndBegin(.polyglotLanguages(["german", "spanish"]), replacing: previous.publication.applicationID, systemIsDark: false)
    let next = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(next.publication.session?.automaticInputAttemptID, attempt)
    XCTAssertEqual(next.publication.practice?.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(next.appearance, appearance)
    XCTAssertTrue(next.currentSystemIsDark)
    XCTAssertEqual(f.page.state.session.generationState, active.session.generationState)
  }

  func testFuturePolyglotReservationCannotBeUsedForAnotherKey() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let capture = try f.page.captureGeneration(router: f.settings.preferenceConfigurationSaves)
    let lease = try XCTUnwrap(f.settings.preferenceConfigurationSaves.captureLease())
    let words = try WebsiteConfigNativeProfile.editDraft(capture.publication.draft, key: "words", value: .number(8),
      pointsPerRem: 16, context: .init(), testActive: false)
    XCTAssertThrowsError(try f.page.beginFuturePolyglotCommit(owner: lease,
      router: f.settings.preferenceConfigurationSaves, capture: capture, draft: words))
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
    XCTAssertNoThrow(try f.page.captureGeneration(router: f.settings.preferenceConfigurationSaves))
  }

  func testFuturePolyglotSaveCannotOverwriteCompetingRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7,"theme":"nord"}"#,
      pointsPerRem: 16, context: .init())
    var armed = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: {
        if armed {
          armed = false
          do {
            guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
              XCTFail("Competing writer failed"); return nil
            }
          } catch { XCTFail("Competing writer: \(error)"); return nil }
        }
        return f.window
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication
    armed = true
    do { try await workflow.editAndBegin(.polyglotLanguages(["english", "spanish"]), replacing: old.applicationID, systemIsDark: false); XCTFail("Competing record overwritten") }
    catch {}
    XCTAssertFalse(armed)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old.applicationID)
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
    XCTAssertNil(f.page.state.configurationDeparture)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing competing record") }
    XCTAssertEqual(saved["theme"], .string("nord"))
    XCTAssertEqual(saved["words"], .number(7))
  }

  func testFuturePolyglotNoticeDoesNotLeakIntoAccountChangedAtPublication() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    withObservationTracking { _ = f.page.state.presentation } onChange: {
      MainActor.assumeIsolated {
        f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
        f.account.localNotices.post("New account", options: .init(durationMilliseconds: 0))
      }
    }
    let message = try await f.workflow.editAndBegin(.polyglotLanguages(["english", "spanish"]), replacing: old, systemIsDark: false)
    XCTAssertTrue(message.contains("已保存"))
    XCTAssertEqual(f.account.localNotices.history.map(\.message), ["New account"])
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
  }

  func testFuturePolyglotCancellationAfterCASReportsSavedWithoutPostingLateNotice() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let handle = WeakWorkflow(); handle.value = f.workflow
    withObservationTracking { _ = f.page.state.presentation } onChange: {
      MainActor.assumeIsolated { handle.value?.cancel() }
    }
    let message = try await f.workflow.editAndBegin(.polyglotLanguages(["german", "spanish"]), replacing: old, systemIsDark: false)
    XCTAssertTrue(message.contains("已保存"))
    XCTAssertEqual(f.page.state.presentation?.publication.draft.generators.polyglotLanguages, [.german, .spanish])
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing saved setting") }
    XCTAssertEqual(saved["customPolyglot"], .array([.string("german"), .string("spanish")]))
  }

  func testFuturePolyglotCancellationBeforePreparationDoesNotSaveOrDepart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("x"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    let task = Task { try await f.workflow.editAndBegin(.polyglotLanguages(["german", "spanish"]), replacing: old, systemIsDark: false) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled setting saved") } catch is CancellationError {}
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old)
    XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testMemoryRealPageRestartRestoresPreviewWithoutInventingAnIdleCountdown() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["memory"],"keymapMode":"next"}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertEqual(publication.draft.keyboardTypography.guideMode, .react)
    XCTAssertTrue(publication.draft.presentation.showAllPracticeLines)
    let attempt = f.page.state.session.automaticInputAttemptID
    var state = f.page.state
    XCTAssertFalse(state.session.tick(at: Date.now.addingTimeInterval(100_000)))
    XCTAssertTrue(state.session.promptGlyphs.allSatisfy { $0.state != .hidden })
    state.session.insertBatch(String(state.session.prompt.prefix(1)))
    XCTAssertTrue(state.session.promptGlyphs.allSatisfy { $0.state == .hidden })
    f.page.replace(state)
    let restarted = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID())
    XCTAssertTrue(restarted)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.state.session.hasStarted)
    XCTAssertTrue(f.page.state.session.promptGlyphs.allSatisfy { $0.state != .hidden })
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
  }

  func testFunboxClearRestoresWindowMemoryAfterFullImportWithoutInheritingItInAnotherWindow() async throws {
    let f = try Fixture(), other = try Fixture(); defer { f.close(); other.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["simon_says"],"keymapMode":"react"}"#, systemIsDark: false)
    let replacement = #"{"mode":"words","words":4,"funbox":["simon_says"],"keymapMode":"off"}"#
    try await f.workflow.apply(json: replacement, systemIsDark: false)
    try await other.workflow.apply(json: replacement, systemIsDark: false)
    for fixture in [f, other] {
      let id = try XCTUnwrap(fixture.page.state.presentation).publication.applicationID
      try await fixture.workflow.editAndBegin(.funboxes([]), replacing: id, systemIsDark: false)
    }
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .react)
    XCTAssertEqual(other.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .off)
  }

  func testFunboxClearAfterOrdinaryRestartRetainsEarliestMemoryAndRejectsOldCommand() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["simon_says"],"keymapMode":"react"}"#, systemIsDark: false)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let restarted = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID())
    XCTAssertTrue(restarted)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old, "Ordinary restarts retain the configuration identity")
    try await f.workflow.editAndBegin(.words(5), replacing: old, systemIsDark: false)
    let current = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    XCTAssertNotEqual(old, current)
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    do { try await f.workflow.editAndBegin(.funboxes([]), replacing: old, systemIsDark: false); XCTFail("Retired command applied") }
    catch {}
    XCTAssertEqual(try register.read().revision, revision)
    try await f.workflow.editAndBegin(.funboxes([]), replacing: current, systemIsDark: false)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .react)
  }

  func testRefusedFunboxSelectionRestoresRuntimeButDoesNotSaveOrRepeatDepartureOnResume() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var fail = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if fail { throw Failure.provider }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"funbox":["simon_says"],"keymapMode":"off"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let register = WebsiteConfigFileRegister(directory: f.directory), before = try register.read()
    fail = true
    do { try await workflow.editAndBegin(.funboxes(["binary"]), replacing: old, systemIsDark: false); XCTFail("Provider failure delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertFalse(error.configurationWasSaved)
      XCTAssertTrue(error.localizedDescription.contains("选择未保存"))
      XCTAssertFalse(error.localizedDescription.contains("设置已保存"))
    }
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertFalse(pending.configurationWasSaved)
    do { try await workflow.editAndBegin(.words(5), replacing: old, systemIsDark: false); XCTFail("Pending preparation replaced") }
    catch let error as LocalizedError { XCTAssertFalse(error.errorDescription?.contains("设置已保存") == true) }
    XCTAssertEqual(pending.draft.projection.runtime["funbox"], .array([.string("simon_says")]))
    XCTAssertEqual(pending.draft.funboxMemory.entries.first?.value, .string("off"))
    XCTAssertEqual(try register.read().revision, before.revision)
    XCTAssertEqual(try register.read().state, before.state)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .notice }.count, 1)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .error }.count, 3)
    fail = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, before.revision)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .notice }.count, 1)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .error }.count, 3)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .next)
    try await workflow.editAndBegin(.funboxes([]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .off)
  }

  func testFunboxClearCannotRemoveActiveNoQuitOrConsumeItsMemory() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["simon_says","no_quit"],"keymapMode":"off"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let original = try XCTUnwrap(f.page.state.presentation).publication
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    do { try await f.workflow.editAndBegin(.funboxes([]), replacing: original.applicationID, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch {}
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, original.applicationID)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.funboxMemory, original.draft.funboxMemory)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(try register.read().revision, revision)
  }

  func testPolyglotDirectionConflictSavesFirstLanguageAndRetainsArabicNosaveListener() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"english","funbox":["polyglot"],"customPolyglot":["arabic","hebrew"],"lazyMode":false}"#, systemIsDark: false)
    let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertEqual(draft.testParameters.language, .arabic)
    XCTAssertTrue(draft.generators.lazyMode, "The Arabic listener applies after its saving language setter")
    XCTAssertEqual(f.page.state.session.configuration.language, .mixedLanguages)
    XCTAssertEqual(f.page.state.session.configuration.polyglotBaseLanguage, .arabic)
    XCTAssertEqual(f.page.state.session.configuration.mixedLanguageComponents, [.arabic, .hebrew])
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing correction") }
    XCTAssertEqual(saved["language"], .string("arabic"))
    XCTAssertEqual(saved["lazyMode"], .bool(false), "Delivery must not save the later nosave listener")
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertEqual(f.account.localNotices.history.first?.level, .notice)
    XCTAssertFalse(try XCTUnwrap(f.account.localNotices.active.first).important)
    XCTAssertEqual(f.account.localNotices.active.first?.durationMilliseconds, 5000)
  }

  func testPolyglotDirectionSetterCheckpointSurvivesNoticeCancellationAndResume() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let handle = WeakWorkflow(), once = NoticeTransition()
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window })
    handle.value = workflow; defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"funbox":["polyglot"],"customPolyglot":["english","german"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated { guard once.calls == 0 else { return }; once.calls += 1; handle.value?.cancel() }
    }
    do { try await workflow.editAndBegin(.language("arabic"), replacing: publication, systemIsDark: false); XCTFail("Cancelled direction correction delivered") }
    catch is CancellationError {}
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.testParameters.language, .english)
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing saved fallback") }
    XCTAssertEqual(saved["language"], .string("english"))
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.page.state.session.configuration.polyglotBaseLanguage, .english)
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testPolyglotDirectionRetryReappliesJoiningGuardBeforeGenerating() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["polyglot","ddoouubblleedd"],"customPolyglot":["arabic","hebrew"]}"#, systemIsDark: false)
    XCTAssertTrue(try XCTUnwrap(f.page.state.presentation).publication.draft.generators.funboxes.isEmpty)
    XCTAssertEqual(f.page.state.session.configuration.language, .arabic)
    XCTAssertEqual(f.account.localNotices.history.count, 2)
    XCTAssertTrue(f.account.localNotices.history.allSatisfy { $0.level == .notice })
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing record") }
    XCTAssertEqual(saved["language"], .string("arabic"))
    XCTAssertEqual(saved["funbox"], .array([.string("polyglot"), .string("ddoouubblleedd")]))
  }

  func testAccountSwitchDuringPolyglotDirectionNoticeCannotDeliverOrEraseTheNewAccountHistory() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["polyglot"],"customPolyglot":["english","spanish"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let once = NoticeTransition()
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated {
        guard once.calls == 0 else { return }; once.calls += 1
        f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
        f.account.localNotices.post("New account", options: .init(durationMilliseconds: 0))
      }
    }
    do { try await f.workflow.editAndBegin(.language("arabic"), replacing: publication, systemIsDark: false); XCTFail("Retired account delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigCommitCoordinatorError.stale = error.underlying else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(once.calls, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication)
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.testParameters.language, .english)
    XCTAssertEqual(f.account.localNotices.history.map(\.message), ["New account"])
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing saved fallback") }
    XCTAssertEqual(saved["language"], .string("english"))
  }

  func testNoQuitRejectsTheLanguageEditBeforePolyglotRecoveryCanSaveOrNotify() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["polyglot","no_quit"],"customPolyglot":["english","german"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    do { try await f.workflow.editAndBegin(.language("arabic"), replacing: publication, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch {}
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testFunboxApplyConfigOverridesReachThePublishedDraftWithoutSavingTemporaryValues() async throws {
    let cases: [(String, [String: WebsiteConfigValue])] = [
      (#"{"mode":"words","words":4,"funbox":["simon_says"],"keymapMode":"off"}"#, ["keymapMode": .string("next")]),
      (#"{"mode":"words","words":4,"funbox":["tts"],"keymapMode":"next"}"#, ["keymapMode": .string("off")]),
      (#"{"mode":"words","words":4,"funbox":["layout_mirror"],"layout":"default","keymapMode":"off"}"#,
        ["layout": .string("qwerty"), "keymapLayout": .string("overrideSync"), "keymapMode": .string("static")]),
      (#"{"mode":"words","words":4,"funbox":["layoutfluid"],"customLayoutfluid":["dvorak","qwerty"],"layout":"default","keymapMode":"off"}"#,
        ["layout": .string("dvorak"), "keymapLayout": .string("dvorak"), "keymapMode": .string("static")]),
      (#"{"mode":"words","words":4,"funbox":["memory"],"keymapMode":"next","showAllLines":false}"#,
        ["keymapMode": .string("react"), "showAllLines": .bool(true)]),
    ]
    for (json, expected) in cases {
      let f = try Fixture(); defer { f.close() }
      let original = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
      try await f.workflow.apply(json: json, systemIsDark: false)
      let published = try XCTUnwrap(f.page.state.presentation).publication.draft
      for (key, value) in expected { XCTAssertEqual(published.projection.runtime[key], value, json + " " + key) }
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(original.projection.runtime))
      XCTAssertTrue(f.account.localNotices.history.isEmpty)
      let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
      try await f.workflow.apply(json: nil, systemIsDark: false)
      let restored = try XCTUnwrap(f.page.state.presentation).publication.draft
      for (key, value) in expected { XCTAssertEqual(restored.projection.runtime[key], value, "restore " + key) }
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    }
  }

  func testJoiningScriptActivationClearsTheEntireFunboxSelectionWithANonImportantNotice() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let json = #"{"mode":"words","words":4,"language":"arabic","funbox":["rot13","ddoouubblleedd"]}"#
    let original = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
    try await f.workflow.apply(json: json, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    XCTAssertTrue(publication.draft.generators.funboxes.isEmpty)
    XCTAssertEqual(f.page.state.session.configuration.language, .arabic)
    XCTAssertFalse(f.page.state.session.configuration.modifiers.contains(.rot13))
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertEqual(f.account.localNotices.history.first?.level, .notice)
    XCTAssertFalse(try XCTUnwrap(f.account.localNotices.active.first).important)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertEqual(try register.read().state, .available(original.projection.runtime), "nosave clear must stay runtime-only")
    try await f.workflow.editAndBegin(.words(5), replacing: publication.applicationID, systemIsDark: false)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing later save") }
    XCTAssertEqual(saved["funbox"], .array([]), "A later real setter saves the current entire runtime")
  }

  func testJoiningClearAfterSavedLanguageSetterSurvivesCancellationWithoutPromotingNosave() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let handle = WeakWorkflow(), register = WebsiteConfigFileRegister(directory: f.directory)
    var cancelArabic = true
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { language in
        if language == .arabic, cancelArabic { handle.value?.cancel() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: language, length: .short)]
      })
    handle.value = workflow; defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"funbox":["ddoouubblleedd"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    do {
      try await workflow.editAndBegin(.language("arabic"), replacing: id, systemIsDark: false)
      XCTFail("Cancelled language preparation delivered")
    } catch is CancellationError {}
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertTrue(pending.draft.generators.funboxes.isEmpty)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing setter save") }
    XCTAssertEqual(saved["language"], .string("arabic"))
    XCTAssertEqual(saved["funbox"], .array([.string("ddoouubblleedd")]))
    let revision = try register.read().revision
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    cancelArabic = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
  }

  func testLazySavingCorrectionPromotesEarlierFunboxNosaveRuntime() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"hindi","funbox":["tts"],"keymapMode":"next","lazyMode":true}"#, systemIsDark: false)
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing record") }
    XCTAssertEqual(saved["keymapMode"], .string("off"))
    XCTAssertEqual(saved["lazyMode"], .bool(false))
    XCTAssertEqual(f.account.localNotices.history.count, 1)
  }

  func testMemoryActivationRepeatsOnEachGenerationAttemptWithoutSavingItsTemporaryValues() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1; if reads < 3 { throw Failure.provider }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    let json = #"{"mode":"quote","quoteLength":[0],"funbox":["memory"],"keymapMode":"next","showAllLines":false}"#
    let original = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
    try await workflow.apply(json: json, systemIsDark: false)
    let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    let activations = draft.projection.events.filter { $0.key == "showAllLines" && $0.newValue == .bool(true) }
    XCTAssertEqual(reads, 3); XCTAssertEqual(activations.count, 3)
    XCTAssertTrue(activations.allSatisfy { $0.nosave == true })
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(original.projection.runtime))
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .error }.count, 2)
  }

  func testCancellingDuringJoiningScriptNoticeStopsBeforeReadingContent() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let handle = WeakWorkflow(), once = NoticeTransition()
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { language in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: language, length: .short)]
      })
    handle.value = workflow; defer { workflow.stop() }
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated { guard once.calls == 0 else { return }; once.calls += 1; handle.value?.cancel() }
    }
    let json = #"{"mode":"quote","quoteLength":[0],"language":"arabic","funbox":["ddoouubblleedd"]}"#
    do { try await workflow.apply(json: json, systemIsDark: false); XCTFail("Retired activation delivered") }
    catch is CancellationError {}
    XCTAssertEqual(reads, 0); XCTAssertTrue(f.account.localNotices.history.isEmpty)
    try assertPendingSavedImport(f)
    try await workflow.apply(json: json, systemIsDark: false)
    XCTAssertEqual(reads, 1); XCTAssertEqual(f.account.localNotices.history.count, 1)
  }

  func testLazyModeNoticeIsOncePerWindowUntilRememberedRestoration() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let unsupported = #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#
    try await f.workflow.apply(json: unsupported, systemIsDark: false)
    let center = f.account.localNotices
    XCTAssertEqual(center.history.count, 1)
    XCTAssertEqual(center.history.first?.level, .notice)
    XCTAssertTrue(center.history.first?.message.contains("语言不支持") == true)
    XCTAssertTrue(center.active.first?.important == true)
    center.clearAll()
    try await f.workflow.apply(json: unsupported, systemIsDark: false)
    XCTAssertEqual(center.history.count, 1, "Re-enabling on an unsupported language does not reset the latch")
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#, systemIsDark: false)
    XCTAssertTrue(f.page.state.presentation?.publication.draft.generators.lazyMode == true)
    try await f.workflow.apply(json: unsupported, systemIsDark: false)
    XCTAssertEqual(center.history.count, 2)
  }

  func testPolyglotLazyModeNoticeNamesTheUnsupportedSelection() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"english","funbox":["polyglot"],"customPolyglot":["hindi","thai"],"lazyMode":true}"#, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertTrue(f.account.localNotices.history.first?.message.contains("所选多语") == true)
    XCTAssertTrue(f.account.localNotices.active.first?.important == true)
    XCTAssertFalse(try XCTUnwrap(f.page.state.presentation).publication.draft.generators.lazyMode)
  }

  func testLazyNoticeSurvivesWorkflowReplacementButIsIndependentInAnotherWindow() async throws {
    let f = try Fixture(), other = try Fixture()
    defer { f.close(); other.close(); f.account.localNotices.clearAll() }
    let json = #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#
    try await f.workflow.apply(json: json, systemIsDark: false)
    f.workflow.stop()
    let replacement = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window })
    defer { replacement.stop() }
    try await replacement.apply(json: json, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    let secondWindow = WebsiteConfigImportWorkflow(page: other.page, settings: other.settings, account: f.account,
      directory: other.directory, readWindow: { other.window })
    defer { secondWindow.stop() }
    try await secondWindow.apply(json: json, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 2)
  }

  func testLazyNoticeDoesNotRepeatOrSpendTheThreeGenerationFailuresBudget() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; throw Failure.provider })
    defer { workflow.stop() }
    for _ in 0..<2 {
      do {
        try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"language":"hindi","lazyMode":true}"#, systemIsDark: false)
        XCTFail("Generation failures delivered")
      } catch let error as WebsiteConfigSavedPreparationError {
        XCTAssertEqual(error.underlying as? Failure, .provider)
      }
    }
    XCTAssertEqual(reads, 6)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .notice }.count, 1)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .error }.count, 6)
    try assertPendingSavedImport(f)
  }

  func testCancellingDuringLazyNoticeWithdrawsItAndAllowsTheNextRequestToWarn() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let handle = WeakWorkflow()
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .hindi, length: .short)]
      })
    handle.value = workflow
    defer { workflow.stop() }
    let transition = NoticeTransition()
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated {
        guard transition.calls == 0 else { return }; transition.calls += 1
        handle.value?.cancel()
      }
    }
    let json = #"{"mode":"quote","quoteLength":[0],"language":"hindi","lazyMode":true}"#
    do { try await workflow.apply(json: json, systemIsDark: false); XCTFail("Cancelled notice request delivered") }
    catch is CancellationError {}
    XCTAssertEqual(reads, 0); XCTAssertTrue(f.account.localNotices.history.isEmpty)
    try assertPendingSavedImport(f)
    try await workflow.apply(json: json, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertEqual(f.account.localNotices.history.first?.level, .notice)
  }

  func testUnauthenticatedFavoritesCorrectionDoesNotConsumeGenerationBudgetOrPostARecoveryNotice() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        if reads < 3 { throw Failure.provider }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[-3,-2,0]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertEqual(f.account.localNotices.history.map(\.level), [.error, .error])
  }

  func testUnauthenticatedFavoritesSetterSavesBeforeProviderAndResumesWithoutAnotherCorrection() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var reads = 0
    let handle = WeakWorkflow()
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        guard case .available(let runtime) = try register.read().state else { throw Failure.provider }
        XCTAssertEqual(runtime["quoteLength"], .array((0...3).map { .number(Double($0)) }), "Correct before the first provider read")
        if reads == 1 { handle.value?.cancel() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    handle.value = workflow
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    do {
      try await workflow.editAndBegin(.quoteLengths([-3]), replacing: publication, systemIsDark: false)
      XCTFail("Cancelled preparation delivered")
    } catch is CancellationError {}
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.quoteSelection.groups, [0,1,2,3])
    let revision = try register.read().revision
    let ledger = f.page.state.priorAttemptLedger
    XCTAssertEqual(ledger.restartCount, 1)
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, ledger.restartCount)
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testAuthenticatedFavoritesAndDormantWordsSelectionDoNotReceiveThePreflightCorrection() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    f.window.favorites = .nativeLocal
    f.settings.favoriteQuoteIDs = ["favorite"]
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "favorite", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[-3]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [-3])
    XCTAssertEqual(f.page.state.practice?.quote?.id, "favorite")
    f.account.currentUser = nil
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[-3]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [-3])
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testUnauthenticatedNativeLocalFavoritesCannotBypassPreflightButSelectedQuoteIsPreserved() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    f.window.favorites = .nativeLocal; f.window.selectedQuoteID = "owned"
    f.settings.favoriteQuoteIDs = ["owned"]
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    for (groups, expected) in [("[-3]", [0,1,2,3]), ("[-2,-3,0]", [0,1,2,3]), ("[-2]", [-2])] {
      try await workflow.apply(json: "{\"mode\":\"quote\",\"quoteLength\":\(groups)}", systemIsDark: false)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, expected)
      XCTAssertEqual(f.page.state.practice?.quote?.id, "owned")
    }
    XCTAssertEqual(reads, 3); XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testAccountChangeAfterFavoritesCorrectionRejectsDeliveryWithoutRevertingItsSavedSetting() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var reads = 0
    var savedRevision: WebsiteConfigFileRegister.Revision?
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1; savedRevision = try register.read().revision
        f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    do {
      try await workflow.editAndBegin(.quoteLengths([-3]), replacing: publication, systemIsDark: false)
      XCTFail("Old account request delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigCommitCoordinatorError.stale = error.underlying else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication)
    XCTAssertEqual(try register.read().revision, savedRevision)
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }
  @MainActor private final class NoticeTransition { var calls = 0 }

  func testGenerationRetriesReachLocalHistoryAndRemainAfterSuccessfulInitialization() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        if reads < 3 { throw NSError(domain: "OwnedGeneration", code: reads,
          userInfo: [NSLocalizedDescriptionKey: "自有目录读取失败 \(reads)"]) }
        return [.init(id: "owned", title: "Owned recovery sample", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop(); f.account.localNotices.clearAll() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 3)
    let entries = f.account.localNotices.history
    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries.map(\.level), [.error, .error])
    XCTAssertTrue(entries.first?.title.contains("1/3") == true)
    XCTAssertTrue(entries.last?.title.contains("2/3") == true)
    XCTAssertTrue(entries.last?.message.contains("自有目录读取失败 2") == true)
    XCTAssertTrue(f.account.localNotices.active.allSatisfy { $0.important && $0.durationMilliseconds == 0 })
    XCTAssertEqual(f.account.localNotices.visible(focused: true).count, 2)
    f.account.localNotices.clearAll()
    XCTAssertEqual(f.account.localNotices.history, entries)
  }

  func testQuoteLengthRecoveryPostsAnImportantNoticeNotAnOrdinaryError() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        [.init(id: "medium", title: "Owned length recovery", text: "ab cd", language: .english, length: .medium)]
      })
    defer { workflow.stop(); f.account.localNotices.clearAll() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertEqual(f.account.localNotices.history.first?.level, .notice)
    XCTAssertTrue(f.account.localNotices.history.first?.message.contains("所选长度") == true)
    XCTAssertTrue(f.account.localNotices.history.first?.message.contains("全部长度") == true)
    XCTAssertTrue(f.account.localNotices.active.first?.important == true)
    XCTAssertEqual(f.account.localNotices.active.first?.durationMilliseconds, 3000)
  }

  func testExhaustedImportReportsLastCauseWithoutFourthNotificationAndKeepsAcceptedRecord() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        throw NSError(domain: "Owned", code: reads, userInfo: [NSLocalizedDescriptionKey: "自有读取失败 \(reads)"])
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Failed import delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertEqual((error.underlying as NSError).code, 3)
      XCTAssertTrue(error.localizedDescription.contains("自有读取失败 3"))
      XCTAssertTrue(error.localizedDescription.contains("三次"))
    }
    XCTAssertEqual(reads, 3); XCTAssertEqual(f.account.localNotices.history.count, 3)
    try assertPendingSavedImport(f)
  }

  func testSilentGenerationErrorsConsumeBudgetWithoutPostingBlankNotices() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1; throw WebsiteWordGenerationError(message: "")
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Silent failures delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertEqual((error.underlying as? WebsiteWordGenerationError)?.message, "")
      XCTAssertTrue(error.localizedDescription.contains("三次"))
    }
    XCTAssertEqual(reads, 3); XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testCancellingFromNotificationObservationWithdrawsTheRetiredReceipt() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; throw Failure.provider })
    defer { workflow.stop() }
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated { workflow.cancel() }
    }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Cancelled notice operation delivered") }
    catch is CancellationError {}
    XCTAssertEqual(reads, 1)
    XCTAssertTrue(f.account.localNotices.history.isEmpty); XCTAssertTrue(f.account.localNotices.active.isEmpty)
    try assertPendingSavedImport(f)
  }

  func testAccountChangeDuringNoticeDeliveryDoesNotLeakRetiredFailure() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; throw Failure.provider })
    defer { workflow.stop() }
    let transition = NoticeTransition()
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated {
        guard transition.calls == 0 else { return }; transition.calls += 1
        f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
        f.account.localNotices.post("New account", options: .init(durationMilliseconds: 0))
      }
    }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Old account operation delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertEqual(error.underlying as? WebsiteConfigCommitCoordinatorError, .stale)
    }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.account.localNotices.history.map(\.message), ["New account"])
    XCTAssertEqual(f.account.localNotices.active.map(\.entry.message), ["New account"])
    XCTAssertEqual(transition.calls, 1)
    try assertPendingSavedImport(f)
  }
  @MainActor private final class Gate {
    var continuation: CheckedContinuation<[OfflineQuote], Never>?
    func read() async -> [OfflineQuote] { await withCheckedContinuation { continuation = $0 } }
    func wait() async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(3))
      while continuation == nil && ContinuousClock.now < deadline { await Task.yield() }
      guard continuation != nil else { throw Failure.notParked }
    }
    func resolve() {
      continuation?.resume(returning: [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)])
      continuation = nil
    }
  }
  @MainActor private final class Fixture {
    let suite = "typebar.import-workflow.\(UUID())"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-import-workflow-\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore()
    let directory: URL
    var window: WebsiteConfigPracticeScopeSource.Window
    lazy var workflow = WebsiteConfigImportWorkflow(page: page, settings: settings, account: account,
      directory: directory, readWindow: { [unowned self] in window })
    init() throws {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
      directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: root)
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, localBackgroundStore: .inMemory())
      account = .init(defaults: defaults)
      window = .init(owner: page.owner, customRecoveryBlocked: false)
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("No legacy write") })
      page.attach(to: settings.preferenceConfigurationSaves)
    }
    func close() {
      workflow.stop(); page.detach()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testImportCommitsActualPageBindsRestartAndLeavesLegacyPreferencesUntouched() async throws {
    let f = try Fixture(); defer { f.close() }
    let old = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"theme":"dracula"}"#, systemIsDark: true)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.theme, .dracula)
    XCTAssertNotNil(f.page.restartController)
    XCTAssertEqual(f.settings.snapshot, old)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertEqual(try register.read().state, .available(try XCTUnwrap(f.page.state.presentation).publication.draft.projection.runtime))
    let first = f.page.state.session.automaticInputAttemptID
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, first)
    guard case .restored = f.page.state.presentation?.publication.draft.origin else { return XCTFail("Restore became import") }
  }

  func testUnsupportedLazyLanguageRemembersAndRestoresAcrossFullImportAndColdRestore() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#, systemIsDark: false)
    let first = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(first.generators.lazyMode)
    XCTAssertEqual(first.lazyMemory, .init(remember: true, prefersArabic: true))
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertEqual(try register.read().lazyMemory, first.lazyMemory)
    let revision = try register.read().revision
    let attempt = f.page.state.session.automaticInputAttemptID
    do {
      try await f.workflow.editAndBegin(.mode(.custom), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Missing custom text applied a candidate lazy-memory restoration")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.customTextUnavailable = error.underlying else {
        return XCTFail("Unexpected saved preparation failure: \(error)")
      }
    }
    XCTAssertNotEqual(try register.read().revision, revision)
    XCTAssertFalse(try register.read().lazyMemory.remember, "Custom init restores the remembered value before missing text is detected")
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.testParameters.mode, .custom)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#, systemIsDark: false)
    let restoredRevision = try register.read().revision
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, restoredRevision, "Stable remembered state must not invalidate other windows on cold restore")
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#, systemIsDark: false)
    let restored = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertTrue(restored.generators.lazyMode)
    XCTAssertFalse(restored.lazyMemory.remember)
    XCTAssertTrue(f.page.state.session.configuration.modifiers.contains(.lazyLatin))
    XCTAssertEqual(try register.read().lazyMemory, restored.lazyMemory)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testArabicLanguageEventAndExplicitLazyPreferencePersistWithoutUsingLegacyPreference() async throws {
    let f = try Fixture(); defer { f.close() }
    f.settings.prefersArabicLazyInput = false
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#, systemIsDark: false)
    func edit(_ value: WebsiteConfigPracticeEdit) async throws {
      try await f.workflow.editAndBegin(value, replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    }
    try await edit(.language("arabic"))
    var draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertTrue(draft.generators.lazyMode); XCTAssertTrue(draft.lazyMemory.prefersArabic)
    XCTAssertTrue(draft.projection.events.contains { $0.key == "lazyMode" && $0.nosave == true })
    guard case .edited(let source) = draft.origin else { return XCTFail("Language became import") }
    XCTAssertEqual(source.key, "language")
    try await edit(.lazyMode(false))
    draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(draft.generators.lazyMode); XCTAssertFalse(draft.lazyMemory.prefersArabic)
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    try await edit(.language("spanish")); try await edit(.language("arabic"))
    draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(draft.generators.lazyMode); XCTAssertFalse(draft.lazyMemory.prefersArabic)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().lazyMemory, draft.lazyMemory)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testCancelledAcceptedImportKeepsItsSavedLazyMemoryWithoutInstallingCandidate() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path), attempt = f.page.state.session.automaticInputAttemptID
    let task = Task { try await workflow.apply(json: #"{"mode":"quote","language":"hindi","lazyMode":true,"quoteLength":[0]}"#, systemIsDark: false) }
    try await gate.wait(); task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled lazy transition committed") } catch is CancellationError {}
    XCTAssertNotEqual(try Data(contentsOf: path), bytes)
    try assertPendingSavedImport(f)
    XCTAssertTrue(try WebsiteConfigFileRegister(directory: f.directory).read().lazyMemory.remember)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.lazyMemory, .init())
  }

  func testMissingRestoreAndTypebarBackupNeverChangePageOrCreateDataRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let attempt = f.page.state.session.automaticInputAttemptID
    do { try await f.workflow.apply(json: nil, systemIsDark: false); XCTFail("Missing record accepted") }
    catch WebsiteConfigImportWorkflowError.missing {}
    let backup = try SettingsJSONCommandCodec.export(settings: f.settings.snapshot,
      configuration: .words(5), layoutFluidLayouts: [], testParameterMemory: .defaults)
    do { try await f.workflow.apply(json: backup, systemIsDark: false); XCTFail("Typebar backup accepted as website JSON") }
    catch WebsiteConfigImportWorkflowError.typebarBackup {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testActiveAttemptAndStoppedWorkflowRefuseWithoutWriting() async throws {
    let f = try Fixture(); defer { f.close() }
    var state = f.page.state
    state.session = TypingSession(configuration: .words(2), prompt: "ab cd")
    state.session.insertBatch("a"); f.page.replace(state)
    do { try await f.workflow.apply(json: "{}", systemIsDark: false); XCTFail("Active attempt overwritten") }
    catch WebsiteConfigImportWorkflowError.activeAttempt {}
    f.workflow.stop()
    do { try await f.workflow.apply(json: "{}", systemIsDark: false); XCTFail("Stopped window accepted") }
    catch WebsiteConfigImportWorkflowError.unavailable {}
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testDirectoryIsPrivateAndUnsafeExistingDirectoryIsNotChmoded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-location-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: root)
    XCTAssertEqual(directory.lastPathComponent, "WebsiteConfiguration")
    let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o700)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    XCTAssertThrowsError(try WebsiteConfigStorageDirectory.prepare(applicationSupport: root))
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
  }

  func testCancelOrForcedSessionReplacementCannotDeliverAcceptedImportAndConcurrentApplyIsRejected() async throws {
    for cancel in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      let task = Task { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false) }
      try await gate.wait()
      do { try await workflow.apply(json: "{}", systemIsDark: false); XCTFail("Concurrent apply accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      if cancel { workflow.cancel() }
      else {
        // Physical input is already suspended. Force an authoritative model
        // replacement to retain the independent generation-staleness check.
        XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
        var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      }
      gate.resolve()
      do { _ = try await task.value; XCTFail("Late generation committed") }
      catch {
        let underlying = (error as? WebsiteConfigSavedPreparationError)?.underlying ?? error
        guard underlying is CancellationError || (underlying as? WebsiteConfigCommitCoordinatorError) == .stale else {
          return XCTFail("Unexpected error: \(error)")
        }
      }
      XCTAssertNil(f.page.state.practice)
      try assertPendingSavedImport(f)
    }
  }

  func testPublishedCustomContentKeepsExactTimeAndFiniteSourceOnReimport() async throws {
    let f = try Fixture(); defer { f.close() }
    let timed = WebsiteConfigSessionBuilder.Scope(customText: "Alpha Beta", customTextIsPrepared: true,
      customCompletion: .time, customDurationOverride: 2.5)
    f.window = .published(owner: f.page.owner, revision: UUID(), scope: timed)
    try await f.workflow.apply(json: #"{"mode":"custom"}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.duration, 2.5)
    XCTAssertEqual(f.page.state.practice?.scope.customDurationOverride, 2.5)
    let finite = WebsiteConfigSessionBuilder.Scope(customText: "preview", finiteTextSource: "actual owned source")
    f.window = .published(owner: f.page.owner, revision: UUID(), scope: finite)
    try await f.workflow.apply(json: #"{"mode":"custom"}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.prompt, "actual owned source")
  }

  func testUnknownWebsiteFieldsDoNotMisclassifyAWebsiteConfigurationAsBackup() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":3,"version":99,"settings":{},"configuration":{}}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 3)
  }

  func testSymlinkedApplicationParentIsRefusedWithoutCreatingAnExternalChild() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-symlink-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let elsewhere = root.appendingPathComponent("elsewhere")
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Typebar"), withDestinationURL: elsewhere)
    XCTAssertThrowsError(try WebsiteConfigStorageDirectory.prepare(applicationSupport: root))
    XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("WebsiteConfiguration").path))
  }

  func testObserverRetirementAfterCommitReportsAppliedRatherThanPretendingRollback() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        // Arm after acceptance/checkpoints so this observes final delivery.
        withObservationTracking { _ = f.page.state } onChange: {
          MainActor.assumeIsolated { f.page.detach() }
        }
        return [.init(id: "owned", title: "Owned delivery", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    let message = try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    XCTAssertTrue(message.contains("已保存并应用"))
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertNotNil(f.page.state.practice)
    XCTAssertNil(f.page.restartController)
    guard case .available = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Committed record was falsely rolled back")
    }
  }

  func testExplicitParameterEditsKeepFullProfileAndPersistEditedOrigin() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"time":15,"theme":"dracula","soundVolume":0.3}"#, systemIsDark: false)
    for edit in [WebsiteConfigPracticeEdit.words(7), .mode(.time), .time(30), .time(30)] {
      let before = f.page.state.session.automaticInputAttemptID
      var expected = try XCTUnwrap(f.page.state.presentation).publication.draft.projection.runtime
      expected[edit.key] = edit.value
      try await f.workflow.editAndBegin(edit, replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
      let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
      guard case .edited(let change) = draft.origin else { return XCTFail("Edit became full import") }
      XCTAssertEqual(change.key, edit.key)
      XCTAssertEqual(draft.projection.runtime, expected)
      XCTAssertEqual(draft.projection.runtime["theme"], .string("dracula"))
      XCTAssertEqual(draft.projection.runtime["soundVolume"], .number(0.3))
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(draft.projection.runtime))
      XCTAssertNotNil(f.page.restartController)
    }
    XCTAssertEqual(f.page.state.session.configuration.duration, 30)
    XCTAssertEqual(f.page.state.practice?.parameterMemory.wordLimit, 7)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testRejectedSetterKeepsRecordButAcceptedPreparationFailureRemainsSaved() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let attempt = f.page.state.session.automaticInputAttemptID
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    do { try await f.workflow.editAndBegin(.words(Double(OfficialTestLimitInput.maximumValue) + 1), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("Invalid edit committed") }
    catch {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(try Data(contentsOf: path), bytes)
    XCTAssertNil(f.page.state.configurationDeparture)
    do { try await f.workflow.editAndBegin(.mode(.custom), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("Missing custom text delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.customTextUnavailable = error.underlying else {
        return XCTFail("Unexpected initializer failure")
      }
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.testParameters.mode, .custom)
    XCTAssertNotEqual(try Data(contentsOf: path), bytes)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    try await f.workflow.apply(json: #"{"mode":"words","words":6}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 6)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testEditCancellationOwnerLossAndDiskConflictDoNotCommitLateGeneration() async throws {
    for cause in ["cancel", "task", "input", "owner", "disk"] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
      let attempt = f.page.state.session.automaticInputAttemptID
      let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      let applicationID = try XCTUnwrap(f.page.state.presentation).publication.applicationID
      let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: applicationID, systemIsDark: false) }
      try await gate.wait()
      do { try await workflow.apply(json: "{}", systemIsDark: false); XCTFail("Concurrent import accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      do { try await workflow.editAndBegin(.words(10), replacing: applicationID, systemIsDark: false); XCTFail("Concurrent edit accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      switch cause {
      case "cancel": workflow.cancel()
      case "task": task.cancel()
      case "input":
        var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      case "owner": f.page.detach()
      default:
        let register = WebsiteConfigFileRegister(directory: f.directory)
        let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":9}"#, pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
          return XCTFail("Conflict setup failed")
        }
      }
      let bytes = try Data(contentsOf: path)
      gate.resolve()
      do { _ = try await task.value; XCTFail("Retired edit committed") } catch {}
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(try Data(contentsOf: path), bytes)
      if cause == "input" { XCTAssertEqual(f.page.state.session.typed, "a") }
    }
  }

  func testActiveEditingClosesAndRecordsOldAttemptButCannotBypassMissingProfile() async throws {
    let f = try Fixture(); defer { f.close() }
    do { try await f.workflow.editAndBegin(.words(5), replacing: UUID(), systemIsDark: false); XCTFail("Legacy page edited") } catch {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let attempt = f.page.state.session.automaticInputAttemptID
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    try await f.workflow.editAndBegin(.words(5), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 5)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertFalse(f.page.acceptsAttemptCallback(for: attempt))
    XCTAssertNotNil(f.page.restartController)
  }

  func testActiveEditPersistsAndClosesInputBeforeQuotePreparation() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[0]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let attempt = f.page.state.session.automaticInputAttemptID
    let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: publication.applicationID, systemIsDark: false) }
    defer { task.cancel() }
    try await gate.wait()
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertNotNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.acceptsInput(for: attempt))
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    guard case .available(let runtime) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Setter must already be durable")
    }
    XCTAssertEqual(runtime["mode"], .string("quote"))
    gate.resolve(); _ = try await task.value
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testIdleAndCompletedSetterSaveBeforeLoadAndResumeWithoutIncompleteAccounting() async throws {
    for completed in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":2,"quoteLength":[0]}"#, systemIsDark: false)
      var state = f.page.state
      if completed {
        state.session.insertBatch(state.session.prompt + " ")
        XCTAssertEqual(state.session.outcome, .completed)
      }
      state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
      f.page.replace(state)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
      XCTAssertEqual(f.page.state.priorAttemptLedger, state.priorAttemptLedger)
      XCTAssertFalse(f.page.acceptsInput(for: state.session.automaticInputAttemptID))
      let pending = try XCTUnwrap(f.page.state.configurationDeparture)
      let register = WebsiteConfigFileRegister(directory: f.directory)
      guard case .available(let runtime) = try register.read().state else { return XCTFail("Setter record missing") }
      XCTAssertEqual(runtime["mode"], .string("quote"))
      let disk = try register.read().revision
      task.cancel(); gate.resolve()
      do { _ = try await task.value; XCTFail("Cancelled preparation delivered") } catch is CancellationError {}
      XCTAssertEqual(f.page.state.configurationDeparture?.id, pending.id)
      XCTAssertEqual(try register.read().revision, disk)
      let retry = Task { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false) }
      try await gate.wait(); gate.resolve(); _ = try await retry.value
      XCTAssertEqual(try register.read().revision, disk)
      XCTAssertEqual(f.page.state.priorAttemptLedger, state.priorAttemptLedger)
      XCTAssertNil(f.page.state.configurationDeparture)
      XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    }
  }

  func testCancelledActiveEditCanResumeWithoutSetterReplayOrDuplicateLedger() async throws {
    for cancelTask in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[0]}"#, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      let pending = try XCTUnwrap(f.page.state.configurationDeparture)
      let register = WebsiteConfigFileRegister(directory: f.directory)
      let revision = try register.read().revision
      do { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false); XCTFail("Concurrent resume accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      if cancelTask { task.cancel() } else { workflow.cancel() }
      gate.resolve()
      do { _ = try await task.value; XCTFail("Cancelled candidate delivered") } catch is CancellationError {}
      XCTAssertEqual(f.page.state.configurationDeparture?.id, pending.id)
      XCTAssertEqual(try register.read().revision, revision)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      do { try await workflow.editAndBegin(.words(8), replacing: publication.applicationID, systemIsDark: false); XCTFail("Pending setter replayed") }
      catch WebsiteConfigImportWorkflowError.preparationPending {}
      do { try await workflow.resumeAndBegin(departureID: UUID(), systemIsDark: false); XCTFail("Stale resume accepted") }
      catch WebsiteConfigImportWorkflowError.conflict {}
      let retry = Task { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false) }
      try await gate.wait(); gate.resolve(); _ = try await retry.value
      XCTAssertNil(f.page.state.configurationDeparture)
      XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      XCTAssertEqual(try register.read().revision, revision)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.events.filter { $0.key == "mode" }.count, 1)
      XCTAssertNotNil(f.page.restartController)
    }
  }

  func testProviderFailureReportsSavedStateAndRetryPreservesAcceptedSetting() async throws {
    let f = try Fixture(); defer { f.close() }
    var fail = true
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if fail { throw Failure.provider }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[0]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    do {
      try await workflow.editAndBegin(.mode(.quote), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Failed provider delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertEqual(error.underlying as? Failure, .provider)
    }
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let revision = try register.read().revision
    do { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false); XCTFail("Failed retry delivered") }
    catch is WebsiteConfigSavedPreparationError {}
    XCTAssertEqual(try register.read().revision, revision)
    fail = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testWorkflowCancelAndResumeKeepAlreadySavedInitCorrection() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var suspend = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if suspend { return await gate.read() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .hindi, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","language":"hindi","lazyMode":false,"quoteLength":[0],"repeatQuotes":"off"}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    suspend = true
    let task = Task { try await workflow.editAndBegin(.lazyMode(true), replacing: publication.applicationID, systemIsDark: false) }
    try await gate.wait()
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertTrue(try register.read().lazyMemory.remember)
    let disk = try register.read().revision
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertFalse(pending.draft.generators.lazyMode)
    workflow.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled initializer delivered") } catch is CancellationError {}
    XCTAssertEqual(f.page.state.configurationDeparture?.id, pending.id)
    XCTAssertEqual(try register.read().revision, disk)
    let retry = Task { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false) }
    try await gate.wait(); gate.resolve(); _ = try await retry.value
    XCTAssertEqual(try register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.events.filter { $0.key == "lazyMode" }.count, 2)
    XCTAssertNotNil(f.page.restartController)
  }

  func testNoQuitActiveEditLeavesConfigurationAndAttemptLive() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let id = f.page.state.session.automaticInputAttemptID
    do { try await f.workflow.editAndBegin(.words(8), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, id)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testAllPracticeSetterActionsCanRestartAnActivePublishedAttempt() async throws {
    let actions: [WebsiteConfigPracticeEdit] = [.mode(.time), .time(17), .words(6), .difficulty(.expert),
      .punctuation(true), .numbers(true), .quoteLengths([0]), .language("english"), .lazyMode(true)]
    for action in actions {
      let f = try Fixture(); defer { f.close() }
      let legacy = f.settings.snapshot
      try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish"}"#, systemIsDark: false)
      let old = f.page.state.session.automaticInputAttemptID
      var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      try await f.workflow.editAndBegin(action, replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, old, action.key)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1, action.key)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime[action.key], action.value, action.key)
      XCTAssertEqual(f.settings.snapshot, legacy, action.key)
      XCTAssertNil(f.page.state.configurationDeparture, action.key)
    }
  }

  func testObservationRetirementAfterSaveDoesNotReportSetterRollback() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.page.detach() }
    }
    let message = try await f.workflow.editAndBegin(.words(6), replacing: publication.applicationID, systemIsDark: false)
    XCTAssertTrue(message.contains("设置已保存"))
    XCTAssertTrue(message.contains("窗口已变化"))
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.testParameters.wordLimit, 6)
    guard case .available(let runtime) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Accepted setting lost")
    }
    XCTAssertEqual(runtime["words"], .number(6))
    do { try await f.workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false); XCTFail("Detached window resumed") }
    catch is WebsiteConfigSavedPreparationError {}
  }

  func testRetiredEditorCannotEditAReplacementPublication() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    try await f.workflow.apply(json: #"{"mode":"words","words":9}"#, systemIsDark: false)
    do { try await f.workflow.editAndBegin(.words(5), replacing: old, systemIsDark: false); XCTFail("Stale editor applied") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 9)
  }

  func testFinishedAttemptCanEditThroughFormWithoutClearingPriorLedger() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"difficulty":"master"}"#, systemIsDark: false)
    var state = f.page.state
    state.session.insertBatch("§")
    XCTAssertTrue(state.session.isFinished)
    state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
    f.page.replace(state)
    let ledger = f.page.state.priorAttemptLedger
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let oldAttempt = f.page.state.session.automaticInputAttemptID
    let form = WebsiteConfigPracticeEditForm(draft: publication.draft)
    form.limit = "6"
    form.startLimit(timed: false, apply: {
      try await f.workflow.editAndBegin($0, replacing: publication.applicationID, systemIsDark: false)
    })
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking); XCTAssertTrue(form.message?.contains("已保存") == true)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 6)
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldAttempt)
    XCTAssertFalse(f.page.acceptsInput(for: oldAttempt))
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
  }

  func testDifficultyAndContentEditsApplyToRealSessionWithoutReimportingOtherFields() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":8,"theme":"dracula","quoteLength":[0,0,1]}"#, systemIsDark: false)
    for edit in [WebsiteConfigPracticeEdit.difficulty(.expert), .punctuation(true), .numbers(true),
      .difficulty(.master), .punctuation(false), .numbers(false)] {
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      var expected = publication.draft.projection.runtime; expected[edit.key] = edit.value
      try await f.workflow.editAndBegin(edit, replacing: publication.applicationID, systemIsDark: false)
      let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
      XCTAssertEqual(draft.projection.runtime, expected)
      guard case .edited(let change) = draft.origin else { return XCTFail("Edit became import") }
      XCTAssertEqual(change.key, edit.key)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.session.configuration.difficulty, draft.inputRules.difficulty)
      XCTAssertEqual(f.page.state.session.configuration.contentOptions, draft.testParameters.contentOptions)
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(expected))
    }
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testQuoteLengthSameValueRebuildsWeightedQueueButDifficultyPreservesIt() async throws {
    let f = try Fixture(); defer { f.close() }
    let quotes: [OfflineQuote] = [("one", QuoteLength.short), ("two", .short), ("three", .medium)].map {
      .init(id: $0.0, title: "Owned editor sample", text: "ab cd", language: .english, length: $0.1)
    }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in quotes })
    defer { workflow.stop() }
    func budget() throws -> Int? {
      var sampler = try XCTUnwrap(f.page.state.practice?.scope.quoteSampler)
      var budget: Int?
      _ = try sampler.next(randomIndex: { budget = $0; return 0 })
      return budget
    }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0,0,1]}"#, systemIsDark: false)
    XCTAssertEqual(try budget(), 4)
    try await workflow.editAndBegin(.difficulty(.expert), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(try budget(), 3)
    try await workflow.editAndBegin(.quoteLengths([0,0,1]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(try budget(), 4)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,0,1])
    try await workflow.editAndBegin(.mode(.words), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    try await workflow.editAndBegin(.quoteLengths([0,0]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(try budget(), 3)
  }

  func testUnavailableQuoteGroupAutomaticallySavesAllLengthsAndRetries() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let attempt = f.page.state.session.automaticInputAttemptID
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    reads = 0
    let message = try await workflow.editAndBegin(.quoteLengths([3]), replacing: publication.applicationID, systemIsDark: false)
    XCTAssertTrue(message.contains("已改为全部长度"))
    XCTAssertEqual(reads, 2, "Retry only after applying the source recovery")
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNotEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertEqual(f.page.state.practice?.scope.quoteSampler?.selection.groups, [0,1,2,3])
    XCTAssertNotEqual(try Data(contentsOf: path), bytes)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths])
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    try await workflow.editAndBegin(.punctuation(true), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertFalse(f.page.state.session.configuration.contentOptions.includePunctuation)
  }

  func testEmptyQuoteCatalogRecoversToWordsWithoutChangingLanguage() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; return [] })
    defer { workflow.stop() }
    let message = try await workflow.apply(json: #"{"mode":"quote","words":4,"language":"spanish"}"#, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.session.configuration.mode, .words)
    XCTAssertEqual(f.page.state.session.configuration.language, .spanish)
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.wordsMode])
    XCTAssertTrue(message.contains("已切换为词数练习"))
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
  }

  func testQuoteRecoveryStopsAfterThreeAttemptsAndRetainsSavedCorrection() async throws {
    let f = try Fixture(); defer { f.close() }
    var invalid = false, reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned bounded sample", text: "ab", language: .english,
          length: invalid ? .all : .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    reads = 0; invalid = true
    do {
      try await workflow.editAndBegin(.quoteLengths([3]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Unusable catalog delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.quoteRecoveryLimitReached = error.underlying else {
        return XCTFail("Unexpected failure: \(error)")
      }
      XCTAssertTrue(error.localizedDescription.contains("三次"))
    }
    XCTAssertEqual(reads, 3)
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertEqual(pending.draft.projection.events.filter { $0.key == "quoteLength" }.count, 4)
    let disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    invalid = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertNotNil(f.page.restartController)
  }

  func testReaderReconfigurationErrorIsNotMisclassifiedAsSamplerRecovery() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        throw WebsiteConfigSessionBuildError.reconfigurationRequired(["quoteLength": .array((0...3).map { .number(Double($0)) })])
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[3]}"#, systemIsDark: false); XCTFail("Reader failure replaced content") }
    catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.reconfigurationRequired = error.underlying else {
        return XCTFail("Reader error was misclassified: \(error)")
      }
    }
    XCTAssertEqual(reads, 1)
    try assertPendingSavedImport(f)
  }

  func testCancellationDuringAutomaticQuoteRetryKeepsRecoveryAndItsExplanation() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var reads = 0, park = true
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        if reads > 1 && park { return await gate.read() }
        return [.init(id: "owned", title: "Owned retry sample", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[3]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: id, systemIsDark: false) }
    try await gate.wait()
    XCTAssertEqual(reads, 2)
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.quoteSelection.groups, [0,1,2,3])
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let disk = try register.read().revision
    workflow.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled retry delivered") } catch is CancellationError {}
    XCTAssertEqual(try register.read().revision, disk)
    park = false
    let message = try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertTrue(message.contains("已改为全部长度"))
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths])
    XCTAssertEqual(try register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testCompetingRecordStopsAutomaticQuoteRecoveryBeforeRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":9}"#,
      pointsPerRem: 16, context: .init())
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
          throw Failure.provider
        }
        return [.init(id: "owned", title: "Owned conflict sample", text: "ab", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[3]}"#, systemIsDark: false)
    do {
      try await workflow.editAndBegin(.mode(.quote), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Recovery overwrote a competing record")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigCommitCoordinatorError.stale = error.underlying else { return XCTFail("Unexpected error") }
    }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(try register.read().state, .available(competitor.projection.runtime))
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.quoteSelection.groups, [3])
  }

  func testFalseSetterReturnKeepsConfigurationButStillDispatchesOrdinaryRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["binary"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    for edit in [WebsiteConfigPracticeEdit.punctuation(true), .numbers(true), .quoteLengths([99]), .mode(.zen), .time(.nan), .words(-1)] {
      let attempt = f.page.state.session.automaticInputAttemptID
      let message = try await f.workflow.editAndBegin(edit, replacing: publication.applicationID, systemIsDark: false)
      XCTAssertTrue(message.contains("设置未修改"))
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime, publication.draft.projection.runtime)
      XCTAssertFalse(f.page.acceptsInput(for: attempt))
      XCTAssertEqual(try Data(contentsOf: path), bytes)
    }
    try await f.workflow.editAndBegin(.difficulty(.expert), replacing: publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.difficulty, .expert)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime["funbox"], .array([.string("binary")]))
  }

  func testThrownOverrideDoesNotDispatchTheFollowingRestartEvent() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["binary"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let attempt = f.page.state.session.automaticInputAttemptID
    do { try await f.workflow.editAndBegin(.quoteLengths([0]), replacing: publication.applicationID, systemIsDark: false); XCTFail("Throwing override accepted") }
    catch WebsiteConfigProjectionError.failedOverride {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
  }

  func testRejectedRestartCancellationOwnerLossAndDiskConflictKeepRecordAndWeightedQueue() async throws {
    for cause in ["cancel", "task", "owner", "disk"] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      var parked = false
      let quotes: [OfflineQuote] = [("one", QuoteLength.short), ("two", .short), ("three", .medium)].map {
        .init(id: $0.0, title: "Owned rejected restart sample", text: "ab cd", language: .english, length: $0.1)
      }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
          if parked { return await gate.read() }; return quotes
        })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0,0,1],"funbox":["rot13"],"repeatQuotes":"off"}"#, systemIsDark: false)
      var state = f.page.state
      state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
      f.page.replace(state)
      let ledger = state.priorAttemptLedger
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      let controller = try XCTUnwrap(f.page.restartController)
      let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      func budget() throws -> Int? {
        var sampler = try XCTUnwrap(f.page.state.practice?.scope.quoteSampler)
        var result: Int?; _ = try sampler.next(randomIndex: { result = $0; return 0 }); return result
      }
      XCTAssertEqual(try budget(), 4)
      parked = true
      let task = Task { try await workflow.editAndBegin(.mode(.zen), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      XCTAssertTrue(controller.isPreparing); XCTAssertFalse(controller.request())
      XCTAssertFalse(f.page.acceptsInput(for: attempt))
      XCTAssertEqual(f.page.state.restartDepartureAttemptID, attempt)
      switch cause {
      case "cancel": workflow.cancel()
      case "task": task.cancel()
      case "owner": f.page.detach()
      default:
        let register = WebsiteConfigFileRegister(directory: f.directory)
        let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":9}"#, pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
          return XCTFail("Conflict setup failed")
        }
      }
      let bytes = try Data(contentsOf: path)
      gate.resolve()
      do { _ = try await task.value; XCTFail("Retired restart installed") }
      catch {
        XCTAssertTrue(error is CancellationError || (error as? WebsiteConfigImportWorkflowError) == .rejectedRestartFailed)
      }
      XCTAssertFalse(controller.isPreparing)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
      XCTAssertEqual(try Data(contentsOf: path), bytes)
      XCTAssertEqual(try budget(), 4)
      if cause == "cancel" || cause == "task" {
        parked = false
        let message = try await workflow.editAndBegin(.mode(.zen), replacing: publication.applicationID, systemIsDark: false)
        XCTAssertTrue(message.contains("设置未修改"))
        XCTAssertEqual(try budget(), 3, "A false setter must not rebuild the quote-length queue")
        XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
        XCTAssertNil(f.page.state.restartDepartureAttemptID)
      }
    }
  }

  func testBusyOrdinaryRestartIsNotRetiredByAnEdit() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var parked = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if parked { return await gate.read() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off"}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let attempt = f.page.state.session.automaticInputAttemptID
    let controller = try XCTUnwrap(f.page.restartController)
    parked = true; XCTAssertTrue(controller.request()); try await gate.wait()
    do { try await workflow.editAndBegin(.quoteLengths([99]), replacing: publication.applicationID, systemIsDark: false); XCTFail("Busy restart was replaced") }
    catch WebsiteConfigImportWorkflowError.busy {}
    gate.resolve()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while controller.isPreparing && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(controller.isPreparing); XCTAssertNil(controller.message)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
  }

  func testCancellationAtTheDeliveryObservationDoesNotFalselyReportUnappliedRestart() async throws {
    for cause in ["workflow", "task"] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      var parked = false
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
          if parked { return await gate.read() }
          return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
        })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"funbox":["rot13"],"repeatQuotes":"off"}"#, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      parked = true
      let task = Task { try await workflow.editAndBegin(.mode(.zen), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      // Departure has already been accepted. The next state change is the
      // synchronous delivery, not generation or a pre-admission cancellation.
      withObservationTracking { _ = f.page.state } onChange: {
        MainActor.assumeIsolated {
          XCTAssertFalse(f.page.acceptsInput(for: attempt))
          if cause == "workflow" { workflow.cancel() } else { task.cancel() }
        }
      }
      gate.resolve()
      do {
        let message = try await task.value
        XCTAssertTrue(message.contains("设置未修改")); XCTAssertTrue(message.contains("新的练习"))
      } catch { XCTFail("A delivered restart was reported as unapplied: \(error)") }
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
      XCTAssertNil(f.page.state.restartDepartureAttemptID)
    }
  }

  func testFalseSetterCannotBypassActiveNoQuitDepartureAdmission() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["binary","no_quit"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let attempt = state.session.automaticInputAttemptID
    XCTAssertTrue(state.session.hasStarted); XCTAssertFalse(state.session.isFinished)
    do { try await f.workflow.editAndBegin(.punctuation(true), replacing: publication.applicationID, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertEqual(f.page.state.priorAttemptLedger, state.priorAttemptLedger)
  }

  func testCancelledLengthPreparationKeepsPublishedQueueAndResumesSavedSelection() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var parked = false
    let quotes: [OfflineQuote] = [("one", QuoteLength.short), ("two", .short), ("three", .medium)].map {
      .init(id: $0.0, title: "Owned cancellation sample", text: "ab", language: .english, length: $0.1)
    }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if parked { return await gate.read() }; return quotes
      })
    defer { workflow.stop() }
    func budget() throws -> Int? {
      var sampler = try XCTUnwrap(f.page.state.practice?.scope.quoteSampler)
      var budget: Int?; _ = try sampler.next(randomIndex: { budget = $0; return 0 }); return budget
    }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0,0,1]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    parked = true
    let task = Task { try await workflow.editAndBegin(.quoteLengths([0,0,1]), replacing: publication.applicationID, systemIsDark: false) }
    try await gate.wait()
    XCTAssertEqual(try budget(), 4)
    let savedBytes = try Data(contentsOf: path)
    XCTAssertNotEqual(savedBytes, bytes, "A same-value setter still saves before preparation")
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled quote draw applied") } catch is CancellationError {}
    XCTAssertEqual(try budget(), 4)
    XCTAssertEqual(try Data(contentsOf: path), savedBytes)
    parked = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try Data(contentsOf: path), savedBytes)
    XCTAssertEqual(try budget(), 4, "The saved length event rebuilds the pool on eventual delivery")
    try await workflow.editAndBegin(.difficulty(.expert), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(try budget(), 3)
  }
}
