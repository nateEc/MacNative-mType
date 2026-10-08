import SwiftUI

/// Original normalized vector construction. Rounded fingers, palm and thumb
/// contacts encode the pose; no letters, labels or asset-based disambiguation.
struct ASLHandshapeDrawing {
  struct Part {
    var path: Path
    var width: CGFloat
    var isPalm = false
  }
  let parts: [Part]
  let motion: Path?

  init(_ shape: ASLHandshape) {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x, y: y) }
    func line(_ a: CGPoint, _ b: CGPoint) -> Path {
      var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }
    func curve(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
      var p = Path(); p.move(to: a); p.addCurve(to: d, control1: b, control2: c); return p
    }
    var palm = Path()
    palm.move(to: point(29, 52)); palm.addQuadCurve(to: point(72, 52), control: point(49, 43))
    palm.addQuadCurve(to: point(69, 82), control: point(77, 72))
    palm.addLine(to: point(63, 93)); palm.addLine(to: point(37, 93))
    palm.addQuadCurve(to: point(26, 74), control: point(24, 87)); palm.closeSubpath()
    var parts: [Part] = [.init(path: palm, width: 0, isPalm: true)]
    let starts: [CGFloat] = [33, 45, 57, 69], lengths: [CGFloat] = [37, 44, 39, 29]
    var ends: [CGPoint] = []
    var fingers: [Part] = []
    let cup = shape.thumb == .openOpposition || shape.thumb == .touchesAll
    for finger in ASLFinger.allCases {
      let i = finger.rawValue, x = starts[i], start = point(x, 57)
      let path: Path, end: CGPoint
      switch shape[finger] {
      case .extended:
        var dx: CGFloat = 0, dy = -lengths[i]
        if shape.arrangement == .spread { dx = [-12, 0, 12, 19][i] }
        if shape.arrangement == .crossed, i < 2 { dx = i == 0 ? 19 : -14 }
        if shape.arrangement == .angled, i == 1 { dx = 35; dy = -7 }
        end = point(x + dx, 57 + dy)
        path = line(start, end)
      case .folded:
        // A folded finger's knuckle remains visible; its end is on the palm.
        end = point(x, 65)
        path = line(point(x, 52), end)
      case .curved:
        if cup {
          // Side-profile cup: tips separate from thumb in C, touch it in O.
          end = point(shape.thumb == .touchesAll ? 62 : 75, shape.thumb == .touchesAll ? 55 : 33 + CGFloat(i) * 2)
          path = curve(point(32 + CGFloat(i) * 3, 66), point(16 + CGFloat(i) * 3, 23),
            point(62 + CGFloat(i) * 2, 9 + CGFloat(i) * 3), end)
        } else {
          end = shape.thumb == .touchesIndex ? point(31, 48) : point(49, 59)
          path = curve(start, point(x + 9, 27), point(x - 15, 29), end)
        }
      case .hooked:
        if shape.fingers.allSatisfy({ $0 == .hooked }) {
          end = point(x, 65)
          path = line(point(x, 46), end)
        } else {
          end = point(x + 15, 29)
          path = curve(start, point(x - 8, 4), point(x + 25, 4), end)
        }
      }
      ends.append(end); fingers.append(.init(path: path, width: 10))
    }
    let thumb: Path
    var thumbBehind = false
    switch shape.thumb {
    case .alongside: thumb = line(point(28, 76), point(24, 42))
    case .acrossPalm: thumb = curve(point(27, 76), point(33, 69), point(43, 66), point(58, 67))
    case .acrossFist: thumb = curve(point(27, 73), point(30, 52), point(43, 50), point(58, 57))
    case .extended: thumb = line(point(29, 75), point(9, 53))
    case .parallel: thumb = line(point(28, 74), point(20, 23))
    case .underFingers(let count):
      thumbBehind = true
      thumb = curve(point(27, 76), point(30, 60), point(32 + CGFloat(count) * 12, 53),
        point(27 + CGFloat(count) * 12, 45))
    case .touchesIndex: thumb = curve(point(27, 76), point(13, 65), point(16, 49), ends[0])
    case .touchesMiddle:
      let target = shape.arrangement == .angled ? point(55, 55) : ends[1]
      thumb = curve(point(27, 76), point(22, 64), point(32, 53), target)
    case .touchesAll: thumb = curve(point(30, 79), point(40, 85), point(61, 78), point(62, 55))
    case .openOpposition: thumb = curve(point(30, 79), point(45, 87), point(65, 79), point(75, 68))
    }
    if thumbBehind { parts.append(.init(path: thumb, width: 12)) }
    // Draw the far finger first, except R where the crossed index is in front.
    parts.append(contentsOf: shape.arrangement == .crossed ? Array(fingers.reversed()) : fingers)
    if !thumbBehind { parts.append(.init(path: thumb, width: 12)) }
    let angle: CGFloat
    switch shape.orientation {
    case .upright: angle = 0
    case .sideways: angle = -.pi / 2
    case .downward: angle = .pi
    case .angledDown: angle = .pi / 2
    }
    let rotation = CGAffineTransform(translationX: -50, y: -50)
      .concatenating(.init(rotationAngle: angle)).concatenating(.init(translationX: 50, y: 50))
    self.parts = parts.map { .init(path: $0.path.applying(rotation), width: $0.width, isPalm: $0.isPalm) }
    var cue = Path()
    switch shape.motion {
    case .jCurve:
      cue.move(to: point(87, 23)); cue.addCurve(to: point(76, 71),
        control1: point(98, 75), control2: point(92, 88))
      cue.addLine(to: point(76, 82)); cue.move(to: point(76, 71)); cue.addLine(to: point(87, 74))
    case .zZigzag:
      cue.move(to: point(61, 10)); cue.addLines([point(93, 10), point(64, 29), point(95, 29)])
      cue.addLine(to: point(88, 23)); cue.move(to: point(95, 29)); cue.addLine(to: point(87, 34))
    case nil: break
    }
    motion = shape.motion == nil ? nil : cue
  }

  func draw(in context: GraphicsContext, size: CGSize, color: Color) {
    let scale = min(size.width, size.height) / 110
    var context = context
    context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
    context.scaleBy(x: scale, y: scale)
    for part in parts {
      if part.isPalm {
        context.fill(part.path, with: .color(color.opacity(0.18)))
        context.stroke(part.path, with: .color(color), lineWidth: 2)
      } else {
        let outline = part.path.strokedPath(.init(lineWidth: part.width, lineCap: .round, lineJoin: .round))
        let inner = part.path.strokedPath(.init(lineWidth: part.width - 4, lineCap: .round, lineJoin: .round))
        var border = outline; border.addPath(inner)
        // Replace covered pixels in this Canvas, including their alpha. A
        // nearer finger must occlude the tucked thumb or far finger, without
        // painting a guessed theme/window background into transparent glyphs.
        context.blendMode = .copy
        context.fill(outline, with: .color(color.opacity(0.18)))
        context.blendMode = .normal
        context.fill(border, with: .color(color), style: .init(eoFill: true))
      }
    }
    if let motion { context.stroke(motion, with: .color(color), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round)) }
  }
}

struct ASLHandshapeGlyph: View {
  let character: Character
  let color: Color
  let background: Color
  let size: CGFloat

  var body: some View {
    Canvas { context, canvasSize in
      if let shape = ASLHandshapePolicy.handshape(for: character) {
        ASLHandshapeDrawing(shape).draw(in: context, size: canvasSize, color: color)
      }
    }
    .frame(width: size * 1.02, height: size * 1.10)
    .background(background, in: RoundedRectangle(cornerRadius: size * 0.12))
    .accessibilityLabel(accessibilityPrompt)
  }

  var accessibilityPrompt: String {
    switch ASLHandshapePolicy.motionCue(for: character) {
    case .jCurve: "ASL 指语字形，J 弧线运动轨迹"
    case .zZigzag: "ASL 指语字形，Z 折线运动轨迹"
    case nil: "ASL 指语字形"
    }
  }
}
