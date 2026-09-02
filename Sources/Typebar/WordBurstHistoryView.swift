import SwiftUI

struct WordBurstHistoryView: View {
    let bursts: [Int]
    let accent: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("近期词速")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array(bursts.enumerated()), id: \.offset) { _, burst in
                Capsule()
                    .fill(accent.opacity(0.72))
                    .frame(width: 5, height: max(4, min(16, CGFloat(burst) / 12)))
                    .accessibilityLabel("\(burst) WPM")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("近期单词速度")
        .accessibilityValue(bursts.map { "\($0) WPM" }.joined(separator: "，"))
    }
}
