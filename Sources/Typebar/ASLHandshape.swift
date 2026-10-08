import Foundation

enum ASLFinger: Int, CaseIterable { case index, middle, ring, little }
enum ASLFingerPose: Hashable { case folded, extended, curved, hooked }
enum ASLThumbPose: Hashable {
  case alongside, acrossPalm, acrossFist, extended, parallel
  case underFingers(Int), touchesIndex, touchesMiddle, touchesAll, openOpposition
}
enum ASLFingerArrangement: Hashable { case joined, spread, crossed, angled }
enum ASLHandOrientation: Hashable { case upright, sideways, downward, angledDown }
enum ASLMotionCue: Hashable { case jCurve, zZigzag }

/// Alphabet semantics, not font outlines. Coordinates are independently drawn
/// by ASLHandshapeDrawing; no third-party images, glyphs or traced paths.
struct ASLHandshape: Hashable {
  let fingers: [ASLFingerPose] // index, middle, ring, little; never includes thumb
  let thumb: ASLThumbPose
  var arrangement: ASLFingerArrangement = .joined
  var orientation: ASLHandOrientation = .upright
  var motion: ASLMotionCue? = nil
  subscript(_ finger: ASLFinger) -> ASLFingerPose { fingers[finger.rawValue] }
}

enum ASLHandshapePolicy {
  static func handshape(for character: Character) -> ASLHandshape? {
    // A single ASCII letter only. Unicode case expansion must not silently
    // turn ß, ligatures, accented graphemes or fullwidth letters into ASL.
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first, scalar.isASCII else { return nil }
    let value = scalar.value >= 97 && scalar.value <= 122 ? scalar.value - 32 : scalar.value
    let folded: ASLFingerPose = .folded, up: ASLFingerPose = .extended
    let curved: ASLFingerPose = .curved, hooked: ASLFingerPose = .hooked
    switch value {
    case 65: return .init(fingers: [folded, folded, folded, folded], thumb: .alongside)
    case 66: return .init(fingers: [up, up, up, up], thumb: .acrossPalm)
    case 67: return .init(fingers: [curved, curved, curved, curved], thumb: .openOpposition)
    case 68: return .init(fingers: [up, curved, curved, curved], thumb: .touchesMiddle)
    case 69: return .init(fingers: [hooked, hooked, hooked, hooked], thumb: .acrossPalm)
    case 70: return .init(fingers: [curved, up, up, up], thumb: .touchesIndex, arrangement: .spread)
    case 71: return .init(fingers: [up, folded, folded, folded], thumb: .parallel, orientation: .sideways)
    case 72: return .init(fingers: [up, up, folded, folded], thumb: .acrossPalm, orientation: .sideways)
    case 73: return .init(fingers: [folded, folded, folded, up], thumb: .acrossFist)
    case 74: return .init(fingers: [folded, folded, folded, up], thumb: .acrossFist, motion: .jCurve)
    case 75: return .init(fingers: [up, up, folded, folded], thumb: .touchesMiddle, arrangement: .angled)
    case 76: return .init(fingers: [up, folded, folded, folded], thumb: .extended)
    case 77: return .init(fingers: [folded, folded, folded, folded], thumb: .underFingers(3))
    case 78: return .init(fingers: [folded, folded, folded, folded], thumb: .underFingers(2))
    case 79: return .init(fingers: [curved, curved, curved, curved], thumb: .touchesAll)
    case 80: return .init(fingers: [up, up, folded, folded], thumb: .touchesMiddle,
      arrangement: .angled, orientation: .angledDown)
    case 81: return .init(fingers: [up, folded, folded, folded], thumb: .parallel, orientation: .downward)
    case 82: return .init(fingers: [up, up, folded, folded], thumb: .acrossPalm, arrangement: .crossed)
    case 83: return .init(fingers: [folded, folded, folded, folded], thumb: .acrossFist)
    case 84: return .init(fingers: [folded, folded, folded, folded], thumb: .underFingers(1))
    case 85: return .init(fingers: [up, up, folded, folded], thumb: .acrossPalm)
    case 86: return .init(fingers: [up, up, folded, folded], thumb: .acrossPalm, arrangement: .spread)
    case 87: return .init(fingers: [up, up, up, folded], thumb: .acrossPalm, arrangement: .spread)
    case 88: return .init(fingers: [hooked, folded, folded, folded], thumb: .acrossFist)
    case 89: return .init(fingers: [folded, folded, folded, up], thumb: .extended, arrangement: .spread)
    case 90: return .init(fingers: [up, folded, folded, folded], thumb: .acrossFist, motion: .zZigzag)
    default: return nil
    }
  }

  static func motionCue(for character: Character) -> ASLMotionCue? { handshape(for: character)?.motion }
  static func usesMotionCue(for character: Character) -> Bool { motionCue(for: character) != nil }
}
