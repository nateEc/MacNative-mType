import SwiftUI

struct NoStressResultView: View {
  let isNewPersonalBest: Bool
  let hasZeroSpeedFeedback: Bool
  let reducesMotion: Bool
  let slowTimer: Bool
  let accent: Color
  let onRestart: () -> Void
  let allowsClosing: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64, weight: .medium))
        .foregroundStyle(.green)
        .accessibilityHidden(true)
      Text("本轮已完成")
        .font(.title2.weight(.semibold))
      Text("无压力结果模式已隐藏本轮的成绩、图表、回放与导出。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      HStack {
        if allowsClosing { Button("关闭") { dismiss() } }
        Spacer()
        Button("再来一次", action: onRestart)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(32)
    .frame(width: 380)
    .overlay {
      ResultCelebrationView(
        isNewPersonalBest: isNewPersonalBest,
        hasZeroSpeedFeedback: hasZeroSpeedFeedback,
        reducesMotion: reducesMotion,
        slowTimer: slowTimer,
        accent: accent,
        text: .primary,
        subduedText: .secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("本轮已完成。无压力结果模式已隐藏本轮的详细结果。")
  }
}
