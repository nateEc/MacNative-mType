import AppKit
import IOKit.hidsystem
import XCTest
@testable import Typebar

@MainActor
final class MusicKeyboardMonitorTests: XCTestCase {
  private final class Voice: TypingSoundVoice {
    var volume: Float = 1
    func copyForPlayback() -> (any TypingSoundVoice)? { Voice() }
    func play(onFinish: @escaping () -> Void) -> Bool { true }
    func stop() {}
  }

  @MainActor private final class Events {
    var handlers: [TypingMusicKeyboardMonitor.Handler] = []
    var masks: [NSEvent.EventTypeMask] = []
    var tokens: [NSObject] = []
    var removed: [NSObject] = []
    var acceptsInstall = true
    var onInstall: (() -> Void)?
    var onRemove: (() -> Void)?
    func install(_ mask: NSEvent.EventTypeMask, _ handler: @escaping TypingMusicKeyboardMonitor.Handler) -> Any? {
      masks.append(mask); handlers.append(handler)
      onInstall?()
      guard acceptsInstall else { return nil }
      let token = NSObject(); tokens.append(token); return token
    }
    func remove(_ token: Any) { removed.append(token as! NSObject); onRemove?() }
    func send(_ event: NSEvent, index: Int? = nil) -> NSEvent? {
      guard let handler = index.map({ handlers[$0] }) ?? handlers.last else { return nil }
      return handler(event)
    }
  }

  @MainActor private final class WeakMonitor {
    weak var value: TypingMusicKeyboardMonitor?
  }

  private func key(_ code: UInt16, type: NSEvent.EventType = .keyDown,
    flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
      timestamp: 0, windowNumber: 0, context: nil, characters: "unrelated text",
      charactersIgnoringModifiers: "unrelated text", isARepeat: repeatKey, keyCode: code))
  }

  private func pitch(_ source: TypingClickPlaybackSource?) -> Double? {
    guard case .musical(_, let tone) = source else { return nil }
    return tone.frequency
  }

  func testOtherResponderKeyDownUpdatesMusicSynchronouslyWithoutPlayingOrChangingEvent() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    let event = try key(12)
    XCTAssertTrue(events.send(event) === event)
    XCTAssertEqual(sources.count, 0)
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
  }

  func testUnmappedGlobalKeyReplacesEarlierPracticePitchAndIsNotForwardedAsInput() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    sound.recordKeyDown(keyCode: 12, modifierFlags: [])
    monitor.start()
    let space = try key(49)
    XCTAssertTrue(events.send(space) === space)
    sound.playClick(style: .pianoTriangle, volume: 0.5)
    XCTAssertEqual(sources.count, 0)
  }

  func testGlobalFlagsChangeUpdatesPreviewOctaveAndKeyUpDoesNotReplaceLastKey() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    _ = events.send(try key(12))
    _ = events.send(try key(56, type: .flagsChanged, flags: .shift))
    sound.previewClick(style: .pianoSine, volume: 0.5)
    _ = events.send(try key(57, type: .flagsChanged, flags: .capsLock))
    sound.previewClick(style: .pianoSine, volume: 0.5)
    _ = events.send(try key(57, type: .flagsChanged))
    sound.previewClick(style: .pianoSine, volume: 0.5)
    _ = events.send(try key(51, type: .keyUp))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(sources.compactMap { pitch($0) }, [523.25, 523.25, 261.63, 261.63])
  }

  func testStartIsSingleInstanceStopRemovesExactTokenAndCanRestart() {
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start(); monitor.start()
    XCTAssertEqual(events.handlers.count, 1)
    XCTAssertEqual(events.masks, [[.keyDown, .flagsChanged]])
    monitor.stop(); monitor.stop()
    XCTAssertEqual(events.removed.count, 1)
    if events.tokens.count == 1, events.removed.count == 1 { XCTAssertTrue(events.tokens[0] === events.removed[0]) }
    monitor.start()
    XCTAssertEqual(events.handlers.count, 2)
    monitor.stop()
    XCTAssertEqual(events.removed.count, 2)
  }

  func testLateStoppedListenerCannotOverwriteTheRestartedListenersPitch() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start(); monitor.stop(); monitor.start()
    guard events.handlers.count == 2 else { XCTFail("missing active listener"); return }
    _ = events.send(try key(12), index: 1)
    let old = try key(6, flags: .shift)
    XCTAssertTrue(events.send(old, index: 0) === old)
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
    monitor.stop()
  }

  func testStartupReadsCapsLockForPreviewWithoutRequiringAKeyDownFirst() {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { .capsLock })
    monitor.start()
    sound.previewClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
    monitor.stop()
  }

  func testApplicationActivationRefreshesCapsWithoutOverwritingPracticeShift() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    var flags: NSEvent.ModifierFlags = []
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { flags })
    let delegate = TypebarApplicationDelegate(musicKeyboardMonitor: monitor)
    delegate.applicationDidFinishLaunching(.init(name: NSApplication.didFinishLaunchingNotification))
    flags = .capsLock
    delegate.applicationDidBecomeActive(.init(name: NSApplication.didBecomeActiveNotification))
    sound.previewClick(style: .pianoSine, volume: 0.5, usesPracticeShift: false)
    XCTAssertEqual(pitch(sources.last), 523.25)
    _ = events.send(try key(56, type: .flagsChanged, flags: [.shift, .capsLock]))
    flags = []
    delegate.applicationDidBecomeActive(.init(name: NSApplication.didBecomeActiveNotification))
    sound.previewClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
    sound.previewClick(style: .pianoSine, volume: 0.5, usesPracticeShift: false)
    XCTAssertEqual(pitch(sources.last), 261.63)
    delegate.applicationWillTerminate(.init(name: NSApplication.willTerminateNotification))
  }

  func testCapsRefreshBeforeStartOrAfterStopDoesNotChangeTheStoredContext() {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    var flags: NSEvent.ModifierFlags = []
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { flags })
    sound.recordKeyDown(keyCode: 12, modifierFlags: .capsLock)
    monitor.refreshCapsLock()
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
    monitor.start()
    flags = .capsLock
    monitor.refreshCapsLock()
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
    monitor.stop()
    flags = []
    monitor.refreshCapsLock()
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
  }

  func testSettingsPreviewIgnoresPracticeShiftButStillUsesIndependentCapsLock() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    for flags: NSEvent.ModifierFlags in [.shift, .capsLock, [.shift, .capsLock], []] {
      sound.updateModifierFlags(flags)
      sound.previewClick(style: .pianoSine, volume: 0.5, usesPracticeShift: false)
    }
    XCTAssertEqual(sources.compactMap { pitch($0) }, [261.63, 523.25, 523.25, 261.63])
  }

  func testStartupDoesNotImportAHeldShiftUntilAMonitoredFlagsEventArrives() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { .shift })
    monitor.start()
    sound.previewClick(style: .pianoSine, volume: 0.5)
    _ = events.send(try key(56, type: .flagsChanged, flags: .shift))
    sound.previewClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(sources.compactMap { pitch($0) }, [261.63, 523.25])
    monitor.stop()
  }

  func testNonKeyboardEventsAreReturnedUnchangedWithoutOverwritingPitchOrModifiers() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    _ = events.send(try key(12))
    let up = try key(6, type: .keyUp, flags: [.shift, .capsLock])
    let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
      modifierFlags: .capsLock, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
    for event in [up, mouse] { XCTAssertTrue(events.send(event) === event) }
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
    monitor.stop()
  }

  func testRepeatAndShortcutKeysUpdatePhysicalCodeRegardlessOfTextButNeverStartAudio() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    let repeatKey = try key(6, flags: [.command, .control], repeatKey: true)
    XCTAssertTrue(events.send(repeatKey) === repeatKey)
    XCTAssertTrue(sources.isEmpty)
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 130.81)
    _ = events.send(try key(65535))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(sources.count, 1)
    monitor.stop()
  }

  func testFailedInstallCanRetryAndItsRetiredHandlerCannotChangeContext() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    events.acceptsInstall = false
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    XCTAssertTrue(events.tokens.isEmpty)
    events.acceptsInstall = true
    monitor.start()
    XCTAssertEqual(events.handlers.count, 2)
    _ = events.send(try key(12), index: 1)
    let failedEvent = try key(6, flags: .shift)
    XCTAssertTrue(events.send(failedEvent, index: 0) === failedEvent)
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
    monitor.stop()
    XCTAssertEqual(events.removed.count, 1)
  }

  func testSynchronousStopDuringInstallRemovesReturnedTokenAndRetiresCallback() throws {
    let events = Events(), reference = WeakMonitor()
    events.onInstall = { reference.value?.stop() }
    let monitor = TypingMusicKeyboardMonitor(install: events.install, remove: events.remove,
      modifierFlags: { [] })
    reference.value = monitor
    monitor.start()
    XCTAssertEqual(events.tokens.count, 1)
    XCTAssertEqual(events.removed.count, 1)
    XCTAssertTrue(events.tokens[0] === events.removed[0])
    let old = try key(12)
    XCTAssertTrue(events.send(old) === old)
    events.onInstall = nil
    monitor.start(); monitor.stop()
    XCTAssertEqual(events.tokens.count, 2)
    XCTAssertEqual(events.removed.count, 2)
  }

  func testSynchronousRepeatedStartDuringInstallDoesNotRegisterAnotherMonitor() {
    let events = Events(), reference = WeakMonitor()
    events.onInstall = { reference.value?.start() }
    let monitor = TypingMusicKeyboardMonitor(install: events.install, remove: events.remove,
      modifierFlags: { [] })
    reference.value = monitor
    monitor.start()
    XCTAssertEqual(events.tokens.count, 1)
    monitor.stop()
    XCTAssertEqual(events.removed.count, 1)
  }

  func testStoppingRetiresCallbackBeforeRemovalAndDoesNotStopANewRegistration() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events(), reference = WeakMonitor()
    let oldEvent = try key(6, flags: .shift)
    events.onRemove = {
      XCTAssertTrue(events.send(oldEvent, index: 0) === oldEvent)
      reference.value?.start()
    }
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    reference.value = monitor
    monitor.start(); monitor.stop()
    XCTAssertEqual(events.tokens.count, 2)
    XCTAssertEqual(events.removed.count, 1)
    _ = events.send(try key(12), index: 1)
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
    events.onRemove = nil
    monitor.stop()
  }

  func testStoppedOwnerIsNotRetainedByCallbackAndReleasedHandlerStillPassesEventThrough() throws {
    let events = Events(), reference = WeakMonitor()
    var monitor: TypingMusicKeyboardMonitor? = .init(install: events.install, remove: events.remove,
      modifierFlags: { [] })
    reference.value = monitor
    monitor?.start(); monitor?.stop(); monitor = nil
    XCTAssertNil(reference.value)
    let event = try key(12)
    XCTAssertTrue(events.send(event) === event)
    XCTAssertEqual(events.removed.count, 1)
  }

  func testActualApplicationDelegateOwnsOneRegistrationAcrossRepeatedLaunchAndExplicitTermination() {
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(install: events.install, remove: events.remove,
      modifierFlags: { [] })
    let delegate = TypebarApplicationDelegate(musicKeyboardMonitor: monitor)
    let launched = Notification(name: NSApplication.didFinishLaunchingNotification)
    delegate.applicationDidFinishLaunching(launched)
    delegate.applicationDidFinishLaunching(launched)
    XCTAssertEqual(events.handlers.count, 1)
    delegate.applicationWillTerminate(.init(name: NSApplication.willTerminateNotification))
    delegate.applicationWillTerminate(.init(name: NSApplication.willTerminateNotification))
    XCTAssertEqual(events.removed.count, 1)
  }

  func testModifierKeyDownReplacesPianoCodeButModifierReleaseLeavesNewLetterCode() throws {
    let cases: [(UInt16, NSEvent.ModifierFlags, UInt)] = [
      (56, .shift, UInt(NX_DEVICELSHIFTKEYMASK)), (60, .shift, UInt(NX_DEVICERSHIFTKEYMASK)),
      (59, .control, UInt(NX_DEVICELCTLKEYMASK)), (62, .control, UInt(NX_DEVICERCTLKEYMASK)),
      (58, .option, UInt(NX_DEVICELALTKEYMASK)), (61, .option, UInt(NX_DEVICERALTKEYMASK)),
      (55, .command, UInt(NX_DEVICELCMDKEYMASK)), (54, .command, UInt(NX_DEVICERCMDKEYMASK)),
    ]
    for (code, flag, bit) in cases {
      var sources: [TypingClickPlaybackSource] = []
      let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
      let events = Events()
      let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
        modifierFlags: { [] })
      monitor.start()
      _ = events.send(try key(12))
      _ = events.send(try key(code, type: .flagsChanged, flags: flag.union(.init(rawValue: bit))))
      sound.playClick(style: .pianoSine, volume: 0.5)
      XCTAssertTrue(sources.isEmpty, "modifier key \(code) must replace Q")
      _ = events.send(try key(12, flags: flag))
      _ = events.send(try key(code, type: .flagsChanged))
      sound.playClick(style: .pianoSine, volume: 0.5)
      XCTAssertEqual(pitch(sources.last), 261.63)
      monitor.stop()
    }
  }

  func testReleasingOneShiftWithOtherSideHeldDoesNotReplaceLastPianoCode() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    let both = NSEvent.ModifierFlags.shift.union(.init(rawValue: UInt(NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK)))
    _ = events.send(try key(56, type: .flagsChanged, flags: .shift.union(.init(rawValue: UInt(NX_DEVICELSHIFTKEYMASK)))))
    _ = events.send(try key(60, type: .flagsChanged, flags: both))
    _ = events.send(try key(12, flags: both))
    _ = events.send(try key(56, type: .flagsChanged, flags: .shift.union(.init(rawValue: UInt(NX_DEVICERSHIFTKEYMASK)))))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
    _ = events.send(try key(60, type: .flagsChanged))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
    monitor.stop()
  }

  func testCapsLockToggleOffIsStillANonPianoKeyDownRatherThanAModifierRelease() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    for flags: NSEvent.ModifierFlags in [.capsLock, []] {
      _ = events.send(try key(12, flags: flags))
      _ = events.send(try key(57, type: .flagsChanged, flags: flags))
      sound.playClick(style: .pianoSine, volume: 0.5)
      XCTAssertTrue(sources.isEmpty)
    }
    monitor.stop()
  }

  func testSyntheticModifierEventsWithoutDeviceBitsRetainAReleaseFallback() throws {
    var sources: [TypingClickPlaybackSource] = []
    let sound = TypingFeedbackSound(loadSound: { sources.append($0); return Voice() }, beep: {})
    let events = Events()
    let monitor = TypingMusicKeyboardMonitor(sound: sound, install: events.install, remove: events.remove,
      modifierFlags: { [] })
    monitor.start()
    _ = events.send(try key(56, type: .flagsChanged, flags: .shift))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertTrue(sources.isEmpty)
    _ = events.send(try key(12, flags: .shift))
    _ = events.send(try key(60, type: .flagsChanged, flags: .shift))
    _ = events.send(try key(12, flags: .shift))
    _ = events.send(try key(56, type: .flagsChanged, flags: .shift))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 523.25)
    _ = events.send(try key(60, type: .flagsChanged))
    sound.playClick(style: .pianoSine, volume: 0.5)
    XCTAssertEqual(pitch(sources.last), 261.63)
    monitor.stop()
  }
}
