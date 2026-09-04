@preconcurrency import AppKit
import SwiftUI

struct NativeTypingInput: NSViewRepresentable {
    var focusRequest: Int
    var quickRestartKey: QuickRestartKey
    var keyboardInputMapping: KeyboardInputMapping
    var keymapLayout: KeyboardLayout
    var oppositeShiftMode: OppositeShiftMode
    var mapsArrowKeysToInput: Bool
    var acceptsNewlineInput: Bool
    var acceptsTabInput: Bool
    var requiresShiftQuickRestart: Bool
    var disablesQuickRestart: Bool
    var enablesLongTestBailout: Bool
    var finishesOnShiftEnter: Bool
    let onInsert: (String, Bool) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onRestart: () -> Void
    let onBailoutArmed: () -> Void
    let onBailout: () -> Void
    let onFinishZen: () -> Void
    let onFocusChanged: (Bool) -> Void
    let onCompositionChanged: (String) -> Void
    let onModifierFlagsChanged: (NSEvent.ModifierFlags) -> Void
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
        view.quickRestartKey = quickRestartKey
        view.keyboardInputMapping = keyboardInputMapping
        view.keymapLayout = keymapLayout
        view.oppositeShiftMode = oppositeShiftMode
        view.mapsArrowKeysToInput = mapsArrowKeysToInput
        view.acceptsNewlineInput = acceptsNewlineInput
        view.acceptsTabInput = acceptsTabInput
        view.requiresShiftQuickRestart = requiresShiftQuickRestart
        view.disablesQuickRestart = disablesQuickRestart
        view.enablesLongTestBailout = enablesLongTestBailout
        view.finishesOnShiftEnter = finishesOnShiftEnter
        view.onBailoutArmed = onBailoutArmed
        view.onBailout = onBailout
        view.onFinishZen = onFinishZen
        view.onFocusChanged = onFocusChanged
        view.onCompositionChanged = onCompositionChanged
        view.onModifierFlagsChanged = onModifierFlagsChanged
        view.onPhysicalKey = onPhysicalKey
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
    var onBailoutArmed: () -> Void = {}
    var onBailout: () -> Void = {}
    var quickRestartKey: QuickRestartKey = .off
    var keyboardInputMapping: KeyboardInputMapping = .system
    var keymapLayout: KeyboardLayout = .ansiQwerty
    var oppositeShiftMode: OppositeShiftMode = .off
    var mapsArrowKeysToInput = false
    var acceptsNewlineInput = false
    var acceptsTabInput = false
    var requiresShiftQuickRestart = false
    var disablesQuickRestart = false
    var enablesLongTestBailout = false
    var finishesOnShiftEnter = false
    var onFinishZen: () -> Void = {}
    var onFocusChanged: (Bool) -> Void = { _ in }
    var onCompositionChanged: (String) -> Void = { _ in }
    var onModifierFlagsChanged: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onPhysicalKey: (UInt16, Bool, Bool) -> Void = { _, _, _ in }

    private var composition = NSAttributedString()
    private var leftShiftPressed = false
    private var rightShiftPressed = false
    private var pendingForcedError = false
    private var lastBailoutAttempt: Date?
    var bailoutClock: () -> Date = { .now }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Typing input")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

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
        onPhysicalKey(event.keyCode, true, event.isARepeat)
        onModifierFlagsChanged(event.modifierFlags)
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
            onRestart()
            return
        }
        if enablesLongTestBailout,
           event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n" {
            handleLongTestBailout()
            return
        }
        if acceptsNewlineInput,
           event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n" {
            if finishesOnShiftEnter, event.modifierFlags.contains(.shift) {
                onFinishZen()
                return
            }
            if quickRestartKey == .enter,
               !disablesQuickRestart,
               event.modifierFlags.contains(.shift) {
                onRestart()
                return
            }
            onInsert("\n", false)
            return
        }
        if acceptsTabInput, event.charactersIgnoringModifiers == "\t" {
            if quickRestartKey == .tab, event.modifierFlags.contains(.shift) {
                onRestart()
                return
            }
            onInsert("\t", false)
            return
        }
        if quickRestartKey.matches(charactersIgnoringModifiers: event.charactersIgnoringModifiers) {
            if disablesQuickRestart { return }
            if requiresShiftQuickRestart, !event.modifierFlags.contains(.shift) { return }
            onRestart()
            return
        }
        if mapsArrowKeysToInput, let arrow = ArrowKeyInputPolicy.character(forKeyCode: event.keyCode) {
            onInsert(String(arrow), false)
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
        if let emulatedCharacter = KeyboardLayoutEmulator.character(
            forKeyCode: event.keyCode, modifierFlags: event.modifierFlags,
            mapping: keyboardInputMapping
        ) {
            onInsert(String(emulatedCharacter), forcesError)
            return
        }
        pendingForcedError = forcesError
        interpretKeyEvents([event])
    }

    override func keyUp(with event: NSEvent) {
        onPhysicalKey(event.keyCode, false, false)
        super.keyUp(with: event)
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

    override func doCommand(by selector: Selector) {
        pendingForcedError = false
        switch selector {
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
        if let attributed = string as? NSAttributedString {
            composition = attributed
        } else {
            composition = NSAttributedString(string: string as? String ?? "")
        }
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
