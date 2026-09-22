@preconcurrency import AppKit
import SwiftUI

enum TypingInputAutofocusDisposition: Equatable {
    case ignore
    case focusAndForward
    case focusAndDiscard
}

/// Keeps the reference's ordinary-key autofocus behavior separate from AppKit
/// monitor lifecycle details, so modal and text-field boundaries are testable.
enum TypingInputAutofocusPolicy {
    static func disposition(
        inputIsFocused: Bool,
        windowIsKey: Bool,
        hasAttachedSheet: Bool,
        externalTextInputIsFocused: Bool,
        charactersIgnoringModifiers: String?,
        commandPressed: Bool,
        controlPressed: Bool,
        discardsAutofocusInput: Bool
    ) -> TypingInputAutofocusDisposition {
        guard !inputIsFocused,
              windowIsKey,
              !hasAttachedSheet,
              !externalTextInputIsFocused,
              !commandPressed,
              !controlPressed,
              let charactersIgnoringModifiers,
              !charactersIgnoringModifiers.isEmpty,
              !["\r", "\n", " ", "\t", "\u{1B}"].contains(charactersIgnoringModifiers)
        else {
            return .ignore
        }
        return discardsAutofocusInput ? .focusAndDiscard : .focusAndForward
  }
}

enum TypingInputEditingCommand: CaseIterable {
  case copy
  case cut
  case paste
  case selectAll
}

/// Practice input has no editable backing buffer. These commands must stay
/// local to the responder instead of reaching a SwiftUI editor or inserting
/// clipboard content into a scored session.
enum TypingInputEditingPolicy {
  static func shouldIntercept(_ command: TypingInputEditingCommand) -> Bool {
    true
  }
}

/// The reference suppresses Home, End, Page, and direction-key browser
/// navigation outside arrow practice. Keep the equivalent AppKit text-system
/// commands local without swallowing unrelated Control-key bindings.
enum TypingInputNavigationPolicy {
  private static let blockedSelectorNames: Set<String> = [
    #selector(NSResponder.moveLeft(_:)),
    #selector(NSResponder.moveRight(_:)),
    #selector(NSResponder.moveUp(_:)),
    #selector(NSResponder.moveDown(_:)),
    #selector(NSResponder.moveWordBackward(_:)),
    #selector(NSResponder.moveWordForward(_:)),
    #selector(NSResponder.moveWordLeft(_:)),
    #selector(NSResponder.moveWordRight(_:)),
    #selector(NSResponder.moveToBeginningOfLine(_:)),
    #selector(NSResponder.moveToEndOfLine(_:)),
    #selector(NSResponder.moveToLeftEndOfLine(_:)),
    #selector(NSResponder.moveToRightEndOfLine(_:)),
    #selector(NSResponder.moveToBeginningOfParagraph(_:)),
    #selector(NSResponder.moveToEndOfParagraph(_:)),
    #selector(NSResponder.moveToBeginningOfDocument(_:)),
    #selector(NSResponder.moveToEndOfDocument(_:)),
    #selector(NSResponder.pageUp(_:)),
    #selector(NSResponder.pageDown(_:)),
    #selector(NSResponder.moveLeftAndModifySelection(_:)),
    #selector(NSResponder.moveRightAndModifySelection(_:)),
    #selector(NSResponder.moveUpAndModifySelection(_:)),
    #selector(NSResponder.moveDownAndModifySelection(_:)),
    #selector(NSResponder.moveBackwardAndModifySelection(_:)),
    #selector(NSResponder.moveForwardAndModifySelection(_:)),
    #selector(NSResponder.moveWordBackwardAndModifySelection(_:)),
    #selector(NSResponder.moveWordForwardAndModifySelection(_:)),
    #selector(NSResponder.moveWordLeftAndModifySelection(_:)),
    #selector(NSResponder.moveWordRightAndModifySelection(_:)),
    #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)),
    #selector(NSResponder.moveToEndOfLineAndModifySelection(_:)),
    #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)),
    #selector(NSResponder.moveToRightEndOfLineAndModifySelection(_:)),
    #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:)),
    #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:)),
    #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)),
    #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)),
    #selector(NSResponder.moveParagraphBackwardAndModifySelection(_:)),
    #selector(NSResponder.moveParagraphForwardAndModifySelection(_:)),
    #selector(NSResponder.pageUpAndModifySelection(_:)),
    #selector(NSResponder.pageDownAndModifySelection(_:)),
    #selector(NSResponder.scrollPageUp(_:)),
    #selector(NSResponder.scrollPageDown(_:)),
    #selector(NSResponder.scrollToBeginningOfDocument(_:)),
    #selector(NSResponder.scrollToEndOfDocument(_:)),
  ].reduce(into: Set<String>()) { $0.insert(NSStringFromSelector($1)) }

  static func shouldIntercept(_ selector: Selector) -> Bool {
    blockedSelectorNames.contains(NSStringFromSelector(selector))
  }
}

struct NativeTypingInput: NSViewRepresentable {
    var focusRequest: Int
    var quickRestartKey: QuickRestartKey
    var keyboardInputMapping: KeyboardInputMapping
    var keymapLayout: KeyboardLayout
    var oppositeShiftMode: OppositeShiftMode
    var mapsArrowKeysToInput: Bool
    var acceptsNewlineInput: Bool
    var acceptsTabInput: Bool
    var discardsAutofocusInput: Bool
    var requiresShiftQuickRestart: Bool
    var disablesQuickRestart: Bool
    var enablesLongTestBailout: Bool
    var finishesOnShiftEnter: Bool
    let onInsert: (String, Bool) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onRestart: () -> Void
    let onOpenCommandPalette: () -> Void
    let onBailoutArmed: () -> Void
    let onBailout: () -> Void
    let onQuickRestartProtectionRequired: () -> Void
    let onFinishZen: () -> Void
    let onFocusChanged: (Bool) -> Void
    let onWindowFocusChanged: (Bool, Bool) -> Void
    let onCompositionStarted: () -> Void
    let onCompositionChanged: (String) -> Void
    let onModifierFlagsChanged: (NSEvent.ModifierFlags) -> Void
    let onKeyDown: (UInt16, String?, NSEvent.ModifierFlags, Bool) -> Void
    let onPhysicalKey: (UInt16, Bool, Bool) -> Void

    final class Coordinator {
        var appliedFocusRequest = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TypingInputView {
        TypingInputView()
    }

    func updateNSView(_ view: TypingInputView, context: Context) {
        view.onInsert = onInsert
        view.onDelete = onDelete
        view.onDeleteWord = onDeleteWord
        view.onRestart = onRestart
        view.onOpenCommandPalette = onOpenCommandPalette
        view.quickRestartKey = quickRestartKey
        view.keyboardInputMapping = keyboardInputMapping
        view.keymapLayout = keymapLayout
        view.oppositeShiftMode = oppositeShiftMode
        view.mapsArrowKeysToInput = mapsArrowKeysToInput
        view.acceptsNewlineInput = acceptsNewlineInput
        view.acceptsTabInput = acceptsTabInput
        view.discardsAutofocusInput = discardsAutofocusInput
        view.requiresShiftQuickRestart = requiresShiftQuickRestart
        view.disablesQuickRestart = disablesQuickRestart
        view.enablesLongTestBailout = enablesLongTestBailout
        view.finishesOnShiftEnter = finishesOnShiftEnter
        view.onBailoutArmed = onBailoutArmed
        view.onBailout = onBailout
        view.onQuickRestartProtectionRequired = onQuickRestartProtectionRequired
        view.onFinishZen = onFinishZen
        view.onFocusChanged = onFocusChanged
        view.onWindowFocusChanged = onWindowFocusChanged
        view.onCompositionStarted = onCompositionStarted
        view.onCompositionChanged = onCompositionChanged
        view.onModifierFlagsChanged = onModifierFlagsChanged
        view.onKeyDown = onKeyDown
        view.onPhysicalKey = onPhysicalKey
        view.refreshWindowFocusState()
        guard context.coordinator.appliedFocusRequest != focusRequest else { return }
        context.coordinator.appliedFocusRequest = focusRequest
        view.resetBailoutAttempt()
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}

final class TypingInputView: NSView, @preconcurrency NSTextInputClient {
    var onInsert: (String, Bool) -> Void = { _, _ in }
    var onDelete: () -> Void = {}
    var onDeleteWord: () -> Void = {}
    var onRestart: () -> Void = {}
    var onOpenCommandPalette: () -> Void = {}
    var onBailoutArmed: () -> Void = {}
    var onBailout: () -> Void = {}
    var onQuickRestartProtectionRequired: () -> Void = {}
    var quickRestartKey: QuickRestartKey = .off
    var keyboardInputMapping: KeyboardInputMapping = .system
    var keymapLayout: KeyboardLayout = .ansiQwerty
    var oppositeShiftMode: OppositeShiftMode = .off
    var mapsArrowKeysToInput = false
    var acceptsNewlineInput = false
    var acceptsTabInput = false
    var discardsAutofocusInput = true
    var requiresShiftQuickRestart = false
    var disablesQuickRestart = false
    var enablesLongTestBailout = false
    var finishesOnShiftEnter = false
    var onFinishZen: () -> Void = {}
    var onFocusChanged: (Bool) -> Void = { _ in }
    var onWindowFocusChanged: (Bool, Bool) -> Void = { _, _ in }
    var onCompositionStarted: () -> Void = {}
    var onCompositionChanged: (String) -> Void = { _ in }
    var onModifierFlagsChanged: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onKeyDown: (UInt16, String?, NSEvent.ModifierFlags, Bool) -> Void = { _, _, _, _ in }
    var onPhysicalKey: (UInt16, Bool, Bool) -> Void = { _, _, _ in }

    private var composition = NSAttributedString()
    private var leftShiftPressed = false
    private var rightShiftPressed = false
    private var pendingForcedError = false
    private var lastBailoutAttempt: Date?
    private weak var observedWindow: NSWindow?
    private var localKeyDownMonitor: Any?
    var bailoutClock: () -> Date = { .now }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Typing input")
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      removeWindowFocusObservers()
      removeLocalKeyDownMonitor()
      super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      removeWindowFocusObservers()
      removeLocalKeyDownMonitor()
      guard let window else { return }
      let center = NotificationCenter.default
      center.addObserver(
        self, selector: #selector(windowDidBecomeKey(_:)),
        name: NSWindow.didBecomeKeyNotification, object: window)
      center.addObserver(
        self, selector: #selector(windowDidResignKey(_:)),
        name: NSWindow.didResignKeyNotification, object: window)
      observedWindow = window
      installLocalKeyDownMonitor(for: window)
      onWindowFocusChanged(window.isKeyWindow, window.attachedSheet != nil)
    }

    override var acceptsFirstResponder: Bool { true }

    func refreshWindowFocusState() {
      guard let window else { return }
      onWindowFocusChanged(window.isKeyWindow, window.attachedSheet != nil)
    }

    private func removeWindowFocusObservers() {
      guard let observedWindow else { return }
      let center = NotificationCenter.default
      center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: observedWindow)
      center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
      self.observedWindow = nil
    }

    private func installLocalKeyDownMonitor(for window: NSWindow) {
      localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
        guard let self, let window, event.window === window else { return event }
        let responder = window.firstResponder
        let externalTextInputIsFocused = responder !== self
          && (responder is NSTextView || responder is NSTextField)
        switch TypingInputAutofocusPolicy.disposition(
          inputIsFocused: responder === self,
          windowIsKey: window.isKeyWindow,
          hasAttachedSheet: window.attachedSheet != nil,
          externalTextInputIsFocused: externalTextInputIsFocused,
          charactersIgnoringModifiers: event.charactersIgnoringModifiers,
          commandPressed: event.modifierFlags.contains(.command),
          controlPressed: event.modifierFlags.contains(.control),
          discardsAutofocusInput: self.discardsAutofocusInput
        ) {
        case .ignore:
          return event
        case .focusAndForward:
          window.makeFirstResponder(self)
          return event
        case .focusAndDiscard:
          window.makeFirstResponder(self)
          return nil
        }
      }
    }

    private func removeLocalKeyDownMonitor() {
      guard let localKeyDownMonitor else { return }
      NSEvent.removeMonitor(localKeyDownMonitor)
      self.localKeyDownMonitor = nil
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
      onWindowFocusChanged(true, window?.attachedSheet != nil)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
      onWindowFocusChanged(false, window?.attachedSheet != nil)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        onFocusChanged(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
      guard super.resignFirstResponder() else { return false }
      leftShiftPressed = false
      rightShiftPressed = false
      pendingForcedError = false
      onModifierFlagsChanged([])
      onFocusChanged(false)
      return true
    }

    override func flagsChanged(with event: NSEvent) {
      switch event.keyCode {
      case 56:
        leftShiftPressed.toggle()
        onPhysicalKey(event.keyCode, leftShiftPressed, false)
      case 60:
        rightShiftPressed.toggle()
        onPhysicalKey(event.keyCode, rightShiftPressed, false)
      default: break
      }
      onModifierFlagsChanged(event.modifierFlags)
      super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if opensCommandPalette(event) {
            if !event.isARepeat { onOpenCommandPalette() }
            return
        }
        onPhysicalKey(event.keyCode, true, event.isARepeat)
        onKeyDown(
            event.keyCode,
            event.charactersIgnoringModifiers,
            event.modifierFlags,
            event.isARepeat)
        onModifierFlagsChanged(event.modifierFlags)
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
            if !event.isARepeat { onRestart() }
            return
        }
        if enablesLongTestBailout,
           event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n" {
            if !event.isARepeat { handleLongTestBailout() }
            return
        }
        if acceptsNewlineInput,
           event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n" {
            if finishesOnShiftEnter, event.modifierFlags.contains(.shift) {
                if !event.isARepeat { onFinishZen() }
                return
            }
            if quickRestartKey == .enter,
               !disablesQuickRestart,
               event.modifierFlags.contains(.shift) {
                if !event.isARepeat { onRestart() }
                return
            }
            onInsert("\n", false)
            return
        }
        if acceptsTabInput, event.charactersIgnoringModifiers == "\t" {
            if quickRestartKey == .tab, event.modifierFlags.contains(.shift) {
                if !event.isARepeat { onRestart() }
                return
            }
            onInsert("\t", false)
            return
        }
        if quickRestartKey.matches(charactersIgnoringModifiers: event.charactersIgnoringModifiers) {
            guard !event.isARepeat else { return }
            if disablesQuickRestart {
                onQuickRestartProtectionRequired()
                return
            }
            if requiresShiftQuickRestart, !event.modifierFlags.contains(.shift) {
                onQuickRestartProtectionRequired()
                return
            }
            onRestart()
            return
        }
        if mapsArrowKeysToInput, let arrow = ArrowKeyInputPolicy.character(forKeyCode: event.keyCode) {
            guard !event.isARepeat else { return }
            onInsert(String(arrow), false)
            return
        }
        if KeyboardLayoutEmulator.performsBackwardDelete(
            forKeyCode: event.keyCode, modifierFlags: event.modifierFlags,
            mapping: keyboardInputMapping
        ) {
            onDelete()
            return
        }
        let shiftComparisonKeyCode: UInt16
        if oppositeShiftMode == .keymap,
           let logicalCharacter = event.characters?.first,
           let mappedKeyCode = KeyboardLayoutEmulator.keyCode(
             for: logicalCharacter, mapping: keyboardInputMapping)
             ?? KeyboardLayoutEmulator.keyCode(for: logicalCharacter, layout: keymapLayout)
        {
            shiftComparisonKeyCode = mappedKeyCode
        } else {
            shiftComparisonKeyCode = event.keyCode
        }
        let forcesError = oppositeShiftMode != .off
          && !OppositeShiftPolicy.usesOppositeShift(
            keyCode: shiftComparisonKeyCode, leftShiftPressed: leftShiftPressed,
            rightShiftPressed: rightShiftPressed)
        if let emulatedText = KeyboardLayoutEmulator.text(
            forKeyCode: event.keyCode, modifierFlags: event.modifierFlags,
            mapping: keyboardInputMapping
        ) {
            onInsert(emulatedText, forcesError)
            return
        }
        pendingForcedError = forcesError
        interpretKeyEvents([event])
    }

    override func keyUp(with event: NSEvent) {
        if opensCommandPalette(event) { return }
        onPhysicalKey(event.keyCode, false, false)
        super.keyUp(with: event)
    }

    private func opensCommandPalette(_ event: NSEvent) -> Bool {
        let fixedShortcut = event.modifierFlags.contains([.command, .shift])
          && !event.modifierFlags.contains(.control)
          && !event.modifierFlags.contains(.option)
          && event.charactersIgnoringModifiers?.lowercased() == "p"
        if fixedShortcut { return true }
        guard !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option)
        else { return false }
        return CommandPaletteDynamicShortcut.resolve(
          quickRestartKey: quickRestartKey, promptAcceptsTab: acceptsTabInput
        ).matches(
          charactersIgnoringModifiers: event.charactersIgnoringModifiers,
          shiftPressed: event.modifierFlags.contains(.shift))
    }

    func resetBailoutAttempt() {
        lastBailoutAttempt = nil
    }

    private func handleLongTestBailout() {
        let now = bailoutClock()
        guard let previous = lastBailoutAttempt,
              now.timeIntervalSince(previous) <= 0.2
        else {
            lastBailoutAttempt = now
            onBailoutArmed()
            return
        }
        lastBailoutAttempt = nil
        onBailout()
    }

    @objc func copy(_ sender: Any?) {
      guard !interceptsEditingCommand(.copy) else { return }
    }

    @objc func cut(_ sender: Any?) {
      guard !interceptsEditingCommand(.cut) else { return }
    }

    @objc func paste(_ sender: Any?) {
      guard !interceptsEditingCommand(.paste) else { return }
    }

    override func selectAll(_ sender: Any?) {
      guard !interceptsEditingCommand(.selectAll) else { return }
    }

    private func interceptsEditingCommand(_ command: TypingInputEditingCommand) -> Bool {
      TypingInputEditingPolicy.shouldIntercept(command)
    }

    override func doCommand(by selector: Selector) {
      pendingForcedError = false
      if TypingInputNavigationPolicy.shouldIntercept(selector) { return }
      switch selector {
        case #selector(copy(_:)):
          guard !interceptsEditingCommand(.copy) else { return }
        case #selector(cut(_:)):
          guard !interceptsEditingCommand(.cut) else { return }
        case #selector(paste(_:)):
          guard !interceptsEditingCommand(.paste) else { return }
        case #selector(selectAll(_:)):
          guard !interceptsEditingCommand(.selectAll) else { return }
        case #selector(NSResponder.deleteWordBackward(_:)):
            onDeleteWord()
        case #selector(deleteBackward(_:)):
            onDelete()
        case #selector(deleteForward(_:)):
            // The practice cursor is fixed at the input end. The reference
            // only processes backward deletion events, so Forward Delete
            // must not erase the preceding typed character.
            break
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)):
            if acceptsNewlineInput { onInsert("\n", false) }
        case #selector(insertTab(_:)):
            if acceptsTabInput { onInsert("\t", false) }
        default:
            super.doCommand(by: selector)
        }
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else {
            text = string as? String ?? ""
        }
        composition = NSAttributedString()
        onCompositionChanged("")
        let forcesError = pendingForcedError
        pendingForcedError = false
        if !text.isEmpty { onInsert(text, forcesError) }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let startsComposition = composition.length == 0
        if let attributed = string as? NSAttributedString {
            composition = attributed
        } else {
            composition = NSAttributedString(string: string as? String ?? "")
        }
        if startsComposition, composition.length > 0 { onCompositionStarted() }
        onCompositionChanged(composition.string)
    }

    func unmarkText() {
        composition = NSAttributedString()
        onCompositionChanged("")
    }

    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }

    func markedRange() -> NSRange {
        composition.length == 0 ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: composition.length)
    }

    func hasMarkedText() -> Bool { composition.length > 0 }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        return window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }
}

enum ArrowKeyInputPolicy {
    static func character(forKeyCode keyCode: UInt16) -> Character? {
        switch keyCode {
        case 126: "↑"
        case 124: "→"
        case 125: "↓"
        case 123: "←"
        default: nil
        }
    }
}
