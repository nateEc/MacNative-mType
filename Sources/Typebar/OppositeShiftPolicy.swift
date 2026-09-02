/// Applies the physical-key opposite-Shift rule using native macOS key codes.
/// The centre locations 6, Y and B belong to both sides and can use either Shift.
enum OppositeShiftPolicy {
  static func usesOppositeShift(
    keyCode: UInt16, leftShiftPressed: Bool, rightShiftPressed: Bool
  ) -> Bool {
    guard leftShiftPressed || rightShiftPressed else { return true }
    let leftSide = leftSideKeyCodes.contains(keyCode)
    let rightSide = rightSideKeyCodes.contains(keyCode)
    guard leftSide || rightSide else { return true }
    return (leftShiftPressed && rightSide) || (rightShiftPressed && leftSide)
  }

  private static let leftSideKeyCodes: Set<UInt16> = [
    50, 18, 19, 20, 21, 23, 22,
    12, 13, 14, 15, 17, 16,
    0, 1, 2, 3, 5,
    56, 6, 7, 8, 9, 11, 49,
  ]

  private static let rightSideKeyCodes: Set<UInt16> = [
    22, 26, 28, 25, 29, 27, 24, 51,
    16, 32, 34, 31, 35, 33, 30, 42,
    4, 38, 40, 37, 41, 39, 36,
    11, 45, 46, 43, 47, 44, 60, 126,
  ]
}
