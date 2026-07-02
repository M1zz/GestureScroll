import CoreGraphics
import AppKit

/// Synthesizes system-level input events so the frontmost app (e.g. Safari) scrolls.
/// Requires Accessibility permission (System Settings ▸ Privacy & Security ▸ Accessibility).
enum SystemControl {

    /// Scroll the frontmost view. Positive `lines` scrolls DOWN (content moves up).
    static func scroll(linesDown lines: Int32) {
        // wheel1 is vertical. Negative = down in CGEvent's convention, so invert.
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .line,
                                  wheelCount: 1,
                                  wheel1: -lines,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Pixel-unit scroll for smooth, drag-like motion. Positive `pixels` scrolls DOWN.
    static func scrollPixels(down pixels: Int32) {
        guard pixels != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: -pixels,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Smoothly scroll by posting several small wheel events.
    static func smoothScroll(linesDown totalLines: Int32, steps: Int = 6) {
        let per = max(1, abs(totalLines) / Int32(steps))
        let sign: Int32 = totalLines >= 0 ? 1 : -1
        for _ in 0..<steps {
            scroll(linesDown: sign * per)
            usleep(12_000) // 12ms between sub-steps
        }
    }

    // MARK: - Mouse (Cursor mode)

    /// Main-display size in global (top-left origin) coordinates — the space
    /// CGEvent mouse events use, matching the camera's normalized coords.
    static var mainDisplaySize: CGSize {
        CGDisplayBounds(CGMainDisplayID()).size
    }

    /// Move the pointer. While `dragging`, posts a left-drag so the press-move-release
    /// sequence reads as a real drag to the frontmost app.
    static func moveMouse(to p: CGPoint, dragging: Bool = false) {
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func mouseDown(at p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func mouseUp(at p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// Press a key with optional modifiers.
    static func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // Common virtual key codes
    static let kPageDown: CGKeyCode = 0x79
    static let kPageUp:   CGKeyCode = 0x74
    static let kRightArrow: CGKeyCode = 0x7C
    static let kLeftArrow:  CGKeyCode = 0x7B
    static let kDownArrow:  CGKeyCode = 0x7D
    static let kUpArrow:    CGKeyCode = 0x7E

    /// Whether the app currently has Accessibility permission.
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user (opens the system dialog the first time).
    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
