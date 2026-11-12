import AppKit
@preconcurrency import ApplicationServices
import KeyboardShortcuts

/// Moves the frontmost application's focused window using macOS Accessibility.
enum WindowDisplayMover {
  static func registerShortcuts() {
    KeyboardShortcuts.onKeyDown(for: .previousDisplay) { move(step: -1) }
    KeyboardShortcuts.onKeyDown(for: .nextDisplay) { move(step: 1) }
    NSLog("Shmacky display shortcuts registered: previous %d, next %d",
          KeyboardShortcuts.isEnabled(for: .previousDisplay), KeyboardShortcuts.isEnabled(for: .nextDisplay))
  }

  static func move(step: Int) {
    NSLog("Shmacky display shortcut invoked; Accessibility permission: %d", AXIsProcessTrusted())
    let screens = NSScreen.screens
    guard screens.count > 1, let primary = screens.first else { return }
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.3)
    // The actual AX request is authoritative: permission preflight can be stale on macOS 27.
    var focusedWindow: CFTypeRef?
    let access = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedWindow)
    guard access == .success else {
      NSLog("Shmacky focused-window request failed: %d", access.rawValue)
      if access == .apiDisabled {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
      }
      return
    }
    guard let value = focusedWindow, CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
    // Core Foundation's runtime type has been checked above.
    let window = unsafeDowncast(value, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(window, 0.3)
    guard (attribute("AXFullScreen", of: window) as? Bool) != true,
          let original = frame(of: window) else { return }
    var movable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable) == .success,
          movable.boolValue else { return }

    // AX uses a top-left origin; AppKit uses a bottom-left origin on the primary screen.
    let appKitFrame = flipped(original, primaryHeight: primary.frame.maxY)
    let ordered = screens.sorted {
      if $0.frame.midX == $1.frame.midX { return $0.frame.midY > $1.frame.midY }
      return $0.frame.midX < $1.frame.midX
    }
    guard let index = sourceIndex(window: appKitFrame, screens: ordered.map(\.frame)) else { return }
    let destination = ordered[(index + step + ordered.count) % ordered.count].visibleFrame
    let transferred = DisplayTransfer.transferredRect(
      window: appKitFrame, source: ordered[index].visibleFrame, destination: destination
    )
    let target = flipped(transferred, primaryHeight: primary.frame.maxY)
    var resizable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable)
    if resizable.boolValue { setSize(target.size, of: window) }
    setPosition(target.origin, of: window)
    // Some apps constrain size to the old screen until the window has moved.
    if resizable.boolValue { setSize(target.size, of: window) }
    if let actual = frame(of: window) {
      let bounds = flipped(destination, primaryHeight: primary.frame.maxY)
      let position = CGPoint(
        x: min(max(target.minX, bounds.minX), max(bounds.minX, bounds.maxX - actual.width)),
        y: min(max(target.minY, bounds.minY), max(bounds.minY, bounds.maxY - actual.height))
      )
      setPosition(position, of: window)
    }
  }

  static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  /// Prefer the display containing the largest part of a spanning window.
  static func sourceIndex(window: CGRect, screens: [CGRect]) -> Int? {
    screens.indices.max { left, right in
      let lhs = window.intersection(screens[left])
      let rhs = window.intersection(screens[right])
      return (lhs.isNull ? 0 : lhs.width * lhs.height) < (rhs.isNull ? 0 : rhs.width * rhs.height)
    }
  }

  private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
  }

  private static func frame(of window: AXUIElement) -> CGRect? {
    guard let position = attribute(kAXPositionAttribute, of: window),
          let size = attribute(kAXSizeAttribute, of: window),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
    return CGRect(origin: point, size: dimensions)
  }

  private static func setPosition(_ position: CGPoint, of window: AXUIElement) {
    var position = position
    guard let value = AXValueCreate(.cgPoint, &position) else { return }
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
  }

  private static func setSize(_ size: CGSize, of window: AXUIElement) {
    var size = size
    guard let value = AXValueCreate(.cgSize, &size) else { return }
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
  }
}
