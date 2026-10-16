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
    if option, let layer = shift ? key.shiftedOptionLabel : key.optionLabel {
      candidate = layer
    } else {
      let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
      candidate = key.legend(
        style: .dynamic, modifierFlags: flags, capsLockEnabled: false)
    }
    // Some official keys intentionally draw no glyph while typing a Space.
    if candidate.isEmpty, key.label.isEmpty,
      key.characters.count == 1, key.characters.contains(" ") {
      return " "
    }
    return Array(candidate).count == 1 ? candidate : nil
  }
}

enum VirtualKeyboardAccessibilityLabel {
  static func label(for output: String, row: Int?, column: Int) -> String {
    guard output == " " else { return "输入 \(output)" }
    if let row {
      return "输入空格（第\(row + 1)排第\(column + 1)键）"
    }
    return "输入空格（底排空格键）"
  }
}

enum VirtualKeyboardVisibleLegend {
  static func text(for key: KeyboardGuideKey, output: String) -> String {
    if output == " ", key.label.isEmpty { return "" }
    return output == " " ? "空格" : output
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
              ForEach(Array(rows[rowIndex].enumerated()), id: \.element.id) { columnIndex, key in
                keyButton(key, row: rowIndex, column: columnIndex)
              }
            }
          }
          HStack(spacing: 5) {
            modifierButton("⇧", active: shift) { shift.toggle() }
            modifierButton("⌥", active: option) { option.toggle() }
            ForEach(Array(KeyboardGuideModel.bottomRow(for: .minimal, layout: layout).enumerated()),
              id: \.element.id) { columnIndex, key in
              keyButton(key, row: nil, column: columnIndex)
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
  private func keyButton(_ key: KeyboardGuideKey, row: Int?, column: Int) -> some View {
    if let output = VirtualKeyboardOutputPolicy.output(for: key, shift: shift, option: option) {
      Button {
        press(output)
      } label: {
        Text(VirtualKeyboardVisibleLegend.text(for: key, output: output))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .frame(width: max(28, key.width), height: 25)
          .foregroundStyle(output == nextCharacter.map(String.init) ? accent : .primary)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityLabel(VirtualKeyboardAccessibilityLabel.label(
        for: output, row: row, column: column))
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
