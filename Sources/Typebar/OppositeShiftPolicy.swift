enum PhysicalKeyboardHand: Hashable {
  case left
  case right
}

/// A local macOS physical-key map shared by input rules and visual feedback.
/// The centre locations 6, Y, B and Space intentionally belong to both hands.
enum PhysicalKeyboardHandMap {
  static func hands(for keyCode: UInt16) -> Set<PhysicalKeyboardHand> {
    var hands = Set<PhysicalKeyboardHand>()
    if leftSideKeyCodes.contains(keyCode) { hands.insert(.left) }
    if rightSideKeyCodes.contains(keyCode) { hands.insert(.right) }
    return hands
  }

  private static let leftSideKeyCodes: Set<UInt16> = [
    50, 18, 19, 20, 21, 23, 22,
    12, 13, 14, 15, 17, 16,
    0, 1, 2, 3, 5, 10,
    56, 6, 7, 8, 9, 11, 49,
  ]

  private static let rightSideKeyCodes: Set<UInt16> = [
    22, 26, 28, 25, 29, 27, 24, 51,
    16, 32, 34, 31, 35, 33, 30, 42,
    4, 38, 40, 37, 41, 39, 36,
    11, 45, 46, 43, 47, 44, 60, 123, 124, 125, 126,
    65, 67, 69, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92,
  ]
}

/// Applies the physical-key opposite-Shift rule using native macOS key codes.
enum OppositeShiftPolicy {
  static func usesOppositeShift(
    keyCode: UInt16, leftShiftPressed: Bool, rightShiftPressed: Bool
  ) -> Bool {
    guard leftShiftPressed || rightShiftPressed else { return true }
    let hands = PhysicalKeyboardHandMap.hands(for: keyCode)
    guard !hands.isEmpty else { return true }
    return (leftShiftPressed && hands.contains(.right)) || (rightShiftPressed && hands.contains(.left))
  }
}
