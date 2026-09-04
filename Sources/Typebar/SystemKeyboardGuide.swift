import Carbon

/// Builds a visual keyboard from the input source macOS is using right now.
/// It asks the system for labels only; text input remains on the standard
/// AppKit/IME path and does not use this map for interpretation.
enum SystemKeyboardGuide {
  enum ModifierLayer {
    case base
    case shift
    case option
    case shiftOption

    var includesShift: Bool {
      self == .shift || self == .shiftOption
    }

    var includesOption: Bool {
      self == .option || self == .shiftOption
    }
  }

  static let physicalRows: [[UInt16]] = [
    [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
    [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
    [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
    [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
  ]

  static func currentRows() -> [[KeyboardGuideKey]]? {
    let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard let rawLayoutData = TISGetInputSourceProperty(
      source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
    guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    let keyboardType = UInt32(LMGetKbdType())
    return rows(
      includesISOSectionKey: keyboardType == UInt32(kKeyboardISO)
    ) { keyCode, layer in
      translatedCharacter(
        layout: layout, keyCode: keyCode, layer: layer, keyboardType: keyboardType)
    }
  }

  /// Convenience overload for tests and callers that only have base/Shift
  /// labels. The system-backed path below uses all four modifier layers.
  static func rows(
    includesISOSectionKey: Bool = false,
    translate: (_ keyCode: UInt16, _ shift: Bool) -> String?
  ) -> [[KeyboardGuideKey]]? {
    rows(includesISOSectionKey: includesISOSectionKey) { keyCode, layer in
      translate(keyCode, layer.includesShift)
    }
  }

  static func rows(
    includesISOSectionKey: Bool = false,
    translateLayer: (_ keyCode: UInt16, _ layer: ModifierLayer) -> String?
  ) -> [[KeyboardGuideKey]]? {
    func mappedKey(_ keyCode: UInt16) -> KeyboardGuideKey? {
      guard let label = normalizedLabel(translateLayer(keyCode, .base)) else { return nil }
      let shiftedLabel = normalizedLabel(translateLayer(keyCode, .shift))
      let optionLabel = normalizedLabel(translateLayer(keyCode, .option))
      let shiftedOptionLabel = normalizedLabel(translateLayer(keyCode, .shiftOption))
      return KeyboardGuideKey(
        "system-\(keyCode)", label: label,
        characters: [label, shiftedLabel, optionLabel, shiftedOptionLabel].compactMap { $0 }.joined(),
        shiftedLabel: shiftedLabel == label ? nil : shiftedLabel,
        optionLabel: optionLabel == label ? nil : optionLabel,
        shiftedOptionLabel: shiftedOptionLabel == optionLabel ? nil : shiftedOptionLabel)
    }
    let mappedRows = physicalRows.map { row in
      row.compactMap(mappedKey)
    }
    guard zip(mappedRows, physicalRows).allSatisfy({ $0.count == $1.count }) else { return nil }
    var rows = mappedRows
    if includesISOSectionKey, let isoSectionKey = mappedKey(10) {
      rows[3].insert(isoSectionKey, at: 0)
    }
    return rows
  }

  private static func translatedCharacter(
    layout: UnsafePointer<UCKeyboardLayout>,
    keyCode: UInt16,
    layer: ModifierLayer,
    keyboardType: UInt32
  ) -> String? {
    var deadKeyState: UInt32 = 0
    var length = 0
    var buffer = Array(repeating: UniChar(0), count: 4)
    var modifiers: UInt32 = 0
    if layer.includesShift { modifiers |= UInt32(shiftKey >> 8) }
    if layer.includesOption { modifiers |= UInt32(optionKey >> 8) }
    let status = UCKeyTranslate(
      layout, keyCode, UInt16(kUCKeyActionDisplay), modifiers, keyboardType,
      OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, buffer.count, &length,
      &buffer)
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: buffer, count: Int(length))
  }

  private static func normalizedLabel(_ value: String?) -> String? {
    guard let value, let character = value.first, !character.isWhitespace, !character.isNewline else {
      return nil
    }
    return String(character)
  }
}
