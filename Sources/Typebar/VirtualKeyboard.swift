import AppKit
import SwiftUI

enum VirtualKeyboardOutputPolicy {
  static func output(
    for key: KeyboardGuideKey, shift: Bool, option: Bool
  ) -> String? {
    if key.id == "space" {
      if shift, let shiftedLabel = key.shiftedLabel { return shiftedLabel }
      return " "
    }
    guard !key.characters.isEmpty else { return nil }
    let candidate: String
    if option {
      guard let layer = shift ? key.shiftedOptionLabel : key.optionLabel else { return nil }
      candidate = layer
    } else {
      let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
      candidate = key.legend(
        style: .dynamic, modifierFlags: flags, capsLockEnabled: false)
    }
    return Array(candidate).count == 1 ? candidate : nil
  }
}

/// A mouse-accessible input surface. It follows the current native layout,
/// while the ordinary keyboard guide remains a display-only hint.
struct VirtualKeyboard: View {
  let layout: KeyboardLayout
  let overrideRows: [[KeyboardGuideKey]]?
  let nextCharacter: Character?
  let accent: Color
  let panel: Color
  let allowsNewline: Bool
  let allowsTab: Bool
  let isEnabled: Bool
  let onInsert: (String) -> Void
  let onDelete: () -> Void

  @State private var shift = false
  @State private var option = false

  private var rows: [[KeyboardGuideKey]] {
    overrideRows ?? KeyboardGuideModel.rows(for: layout)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("鼠标输入", systemImage: "cursorarrow.click.2")
          .font(.caption.weight(.semibold))
        Spacer()
        Text("点击键位输入 · 修饰键单次生效")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      ScrollView(.horizontal) {
        VStack(spacing: 5) {
          ForEach(rows.indices, id: \.self) { rowIndex in
            HStack(spacing: 5) {
              ForEach(rows[rowIndex]) { key in keyButton(key) }
            }
          }
          HStack(spacing: 5) {
            modifierButton("⇧", active: shift) { shift.toggle() }
            modifierButton("⌥", active: option) { option.toggle() }
            ForEach(KeyboardGuideModel.bottomRow(for: .minimal, layout: layout)) { key in
              keyButton(key)
            }
            Button("退格", systemImage: "delete.left") {
              onDelete()
              shift = false
              option = false
            }
              .accessibilityLabel("删除上一个字符")
            if allowsTab {
              Button("制表", systemImage: "arrow.right.to.line") { press("\t") }
            }
            if allowsNewline {
              Button("换行", systemImage: "return") { press("\n") }
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        .padding(.horizontal, 2)
      }
      .scrollIndicators(.hidden)
    }
    .padding(12)
    .background(panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    .disabled(!isEnabled)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("可点击的屏幕键盘")
  }

  @ViewBuilder
  private func keyButton(_ key: KeyboardGuideKey) -> some View {
    if let output = VirtualKeyboardOutputPolicy.output(for: key, shift: shift, option: option) {
      Button {
        press(output)
      } label: {
        Text(output == " " ? "空格" : output)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .frame(width: max(28, key.width), height: 25)
          .foregroundStyle(output == nextCharacter.map(String.init) ? accent : .primary)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityLabel(output == " " ? "输入空格" : "输入 \(output)")
    }
  }

  private func modifierButton(
    _ title: String, active: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .frame(minWidth: 30, minHeight: 25)
        .foregroundStyle(active ? accent : .primary)
    }
    .accessibilityLabel(title == "⇧" ? "切换下一键 Shift" : "切换下一键 Option")
  }

  private func press(_ output: String) {
    onInsert(output)
    shift = false
    option = false
  }
}
