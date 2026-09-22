import AppKit

/// Detects the hidden keyboard-practice sequence without taking ownership of
/// input dispatch. The hosting input view continues processing every event.
struct KonamiSequenceTracker {
  static let destination = URL(string: "https://keymash.io/")!

  private enum Step: Equatable {
    case up
    case down
    case left
    case right
    case letter(String)

    init?(keyCode: UInt16, charactersIgnoringModifiers: String?) {
      switch keyCode {
      case 126: self = .up
      case 125: self = .down
      case 123: self = .left
      case 124: self = .right
      default:
        guard let charactersIgnoringModifiers,
              charactersIgnoringModifiers.count == 1,
              let character = charactersIgnoringModifiers.lowercased().first,
              character == "a" || character == "b"
        else { return nil }
        self = .letter(String(character))
      }
    }
  }

  private static let sequence: [Step] = [
    .up, .up, .down, .down, .left, .right, .left, .right, .letter("b"), .letter("a"),
  ]

  private var nextStepIndex = 0

  mutating func consume(
    keyCode: UInt16,
    charactersIgnoringModifiers: String?,
    modifierFlags: NSEvent.ModifierFlags,
    isRepeat: Bool
  ) -> Bool {
    guard !isRepeat else { return false }
    guard modifierFlags.intersection([.command, .control, .option]).isEmpty else {
      nextStepIndex = 0
      return false
    }
    guard let step = Step(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers)
    else {
      nextStepIndex = 0
      return false
    }

    if step == Self.sequence[nextStepIndex] {
      nextStepIndex += 1
      if nextStepIndex == Self.sequence.count {
        nextStepIndex = 0
        return true
      }
      return false
    }

    nextStepIndex = step == Self.sequence[0] ? 1 : 0
    return false
  }
}
