import AppKit
import CoreGraphics
import Foundation
import Config

/// Executes a `ButtonAction` against the current system state.
public enum ActionDispatcher {

    // MARK: - Public entry point

    /// Perform the action described by `action`.
    /// - Returns: `true` if the original event should be suppressed (consumed
    ///   by the dispatcher), `false` if the caller should pass it through.
    @discardableResult
    public static func perform(_ action: ButtonAction) -> Bool {
        switch action {
        case .default:
            return false   // caller passes the event through

        case .disabled:
            return true    // suppress, do nothing

        case .keyboardShortcut(let combo):
            postKeyCombo(combo)
            return true

        case .systemAction(let sysAction):
            postSystemAction(sysAction)
            return true

        case .openApp(let bundleID):
            openApp(bundleID: bundleID)
            return true

        case .gestureButton:
            // gestureButton is handled upstream by GestureRecognizer; treat as
            // pass-through here so callers that accidentally forward it don't
            // do unexpected work.
            return false
        }
    }

    // MARK: - Keyboard shortcut

    private static func postKeyCombo(_ combo: KeyCombo) {
        var cgFlags = CGEventFlags()

        if combo.modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        if combo.modifiers.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if combo.modifiers.contains(.control) { cgFlags.insert(.maskControl) }
        if combo.modifiers.contains(.shift)   { cgFlags.insert(.maskShift) }

        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: true) {
            down.flags = cgFlags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: false) {
            up.flags = cgFlags
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - System actions

    // Virtual key codes referenced from HIToolbox/Events.h
    private enum VK {
        static let f3:  CGKeyCode = 99   // Mission Control (Expose) on most keyboards
        static let f4:  CGKeyCode = 118  // Launchpad
        static let f9:  CGKeyCode = 101  // (unused here, kept for reference)
        static let f10: CGKeyCode = 109
        static let f11: CGKeyCode = 103  // Show Desktop
        static let f12: CGKeyCode = 111  // Launchpad (alternate)
        static let upArrow:    CGKeyCode = 126
        static let downArrow:  CGKeyCode = 125
        static let leftArrow:  CGKeyCode = 123
        static let rightArrow: CGKeyCode = 124
        static let volumeUp:   CGKeyCode = 72
        static let volumeDown: CGKeyCode = 73
        static let mute:       CGKeyCode = 74
        static let playPause:  CGKeyCode = 100 // NX_KEYTYPE_PLAY mapped via NSSystemDefined
        static let nextTrack:  CGKeyCode = 101 // NX_KEYTYPE_NEXT
        static let prevTrack:  CGKeyCode = 98  // NX_KEYTYPE_PREVIOUS
        // Shift+Cmd+5 is screenshot; Cmd+Space is Spotlight
        static let num5:       CGKeyCode = 23
        static let space:      CGKeyCode = 49
        // Lock screen: Ctrl+Cmd+Q
        static let q:          CGKeyCode = 12
    }

    private static func postSystemAction(_ action: SystemAction) {
        switch action {
        case .missionControl:
            // Ctrl+Up
            postKeyCombo(KeyCombo(keyCode: VK.upArrow, modifiers: .control))

        case .appExpose:
            // Ctrl+Down
            postKeyCombo(KeyCombo(keyCode: VK.downArrow, modifiers: .control))

        case .launchpad:
            // F4 — standard Launchpad key
            postKeyCombo(KeyCombo(keyCode: VK.f4))

        case .switchDesktopLeft:
            // Ctrl+Left — switch to left desktop/full screen app
            postKeyCombo(KeyCombo(keyCode: VK.leftArrow, modifiers: .control))

        case .switchDesktopRight:
            // Ctrl+Right — switch to right desktop/full screen app
            postKeyCombo(KeyCombo(keyCode: VK.rightArrow, modifiers: .control))

        case .showDesktop:
            // F11
            postKeyCombo(KeyCombo(keyCode: VK.f11))

        case .volumeUp:
            postMediaKey(NX_KEYTYPE_SOUND_UP)

        case .volumeDown:
            postMediaKey(NX_KEYTYPE_SOUND_DOWN)

        case .mute:
            postMediaKey(NX_KEYTYPE_MUTE)

        case .playPause:
            postMediaKey(NX_KEYTYPE_PLAY)

        case .nextTrack:
            postMediaKey(NX_KEYTYPE_NEXT)

        case .prevTrack:
            postMediaKey(NX_KEYTYPE_PREVIOUS)

        case .screenshot:
            // Shift+Cmd+5 (macOS 10.14+ screenshot tool)
            postKeyCombo(KeyCombo(keyCode: VK.num5, modifiers: [.shift, .command]))

        case .spotlight:
            // Cmd+Space
            postKeyCombo(KeyCombo(keyCode: VK.space, modifiers: .command))

        case .lockScreen:
            // Ctrl+Cmd+Q
            postKeyCombo(KeyCombo(keyCode: VK.q, modifiers: [.control, .command]))
        }
    }

    // MARK: - Media keys (NX system-defined events)

    /// Posts a media key event using the NSSystemDefined event mechanism.
    /// This is the correct macOS approach for volume/playback keys.
    private static func postMediaKey(_ keyType: Int32) {
        func post(keyDown: Bool) {
            let flags: Int = keyDown ? 0xa00 : 0xb00
            let data1: Int = Int(keyType) << 16 | flags
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,          // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(keyDown: true)
        post(keyDown: false)
    }

    // MARK: - App launch

    private static func openApp(bundleID: String) {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            workspace.openApplication(at: url, configuration: config)
        }
    }
}

// MARK: - NX key type constants (from <IOKit/hidsystem/ev_keymap.h>)

private let NX_KEYTYPE_SOUND_UP:   Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_MUTE:       Int32 = 7
private let NX_KEYTYPE_PLAY:       Int32 = 16
private let NX_KEYTYPE_NEXT:       Int32 = 17
private let NX_KEYTYPE_PREVIOUS:   Int32 = 18
