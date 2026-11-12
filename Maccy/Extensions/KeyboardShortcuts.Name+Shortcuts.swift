import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let previousDisplay = Self(
    "previousDisplay", initial: Shortcut(.leftArrow, modifiers: [.control, .option, .command])
  )
  static let nextDisplay = Self(
    "nextDisplay", initial: Shortcut(.rightArrow, modifiers: [.control, .option, .command])
  )
  static let popup = Self("popup", initial: Shortcut(.c, modifiers: [.command, .shift]))
  static let pin = Self("pin", initial: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", initial: Shortcut(.delete, modifiers: [.option]))
  static let togglePreview = Self("togglePreview", initial: Shortcut(.space, modifiers: [.control]))
}
