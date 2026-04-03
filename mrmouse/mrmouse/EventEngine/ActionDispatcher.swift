import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Executes a `ButtonAction` against the current system state.
public enum ActionDispatcher {

    // MARK: - Public entry point

    @discardableResult
    public static func perform(_ action: ButtonAction) -> Bool {
        switch action {
        case .default:
            return false

        case .disabled:
            return true

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
            return false
        }
    }

    // MARK: - Keyboard shortcut

    private static let ctrlKeyCode: CGKeyCode = 59

    private static func postKeyCombo(_ combo: KeyCombo) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let src else { return }

        var cgFlags = CGEventFlags()
        if combo.modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        if combo.modifiers.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if combo.modifiers.contains(.control) { cgFlags.insert(.maskControl) }
        if combo.modifiers.contains(.shift)   { cgFlags.insert(.maskShift) }

        if combo.modifiers.contains(.control) {
            if let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: ctrlKeyCode, keyDown: true) {
                ctrlDown.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: true) {
            down.flags = cgFlags
            down.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.05)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: false) {
            up.flags = cgFlags
            up.post(tap: .cghidEventTap)
        }
        if combo.modifiers.contains(.control) {
            Thread.sleep(forTimeInterval: 0.01)
            if let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: ctrlKeyCode, keyDown: false) {
                ctrlUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - System actions

    // macOS 26 (Tahoe) key codes for system functions.
    // These are virtual key codes that directly trigger system UI
    // without requiring modifier flags (which CGEvent ignores on Tahoe).
    private enum SK {
        static let missionControl: CGKeyCode = 160
        static let showDesktop:    CGKeyCode = 103
        static let launchpad:      CGKeyCode = 131
        static let emojiPicker:    CGKeyCode = 179
    }

    private static func postSystemAction(_ action: SystemAction) {
        switch action {
        case .missionControl:
            pressKey(SK.missionControl)

        case .appExpose:
            triggerAppExpose()

        case .launchpad:
            pressKey(SK.launchpad)

        case .switchDesktopLeft:
            DesktopSwitcher.switchDesktop(.left)

        case .switchDesktopRight:
            DesktopSwitcher.switchDesktop(.right)

        case .showDesktop:
            pressKey(SK.showDesktop)

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
            postKeyCombo(KeyCombo(keyCode: 23, modifiers: [.shift, .command]))

        case .spotlight:
            postKeyCombo(KeyCombo(keyCode: 49, modifiers: .command))

        case .lockScreen:
            postKeyCombo(KeyCombo(keyCode: 12, modifiers: [.control, .command]))
        }
    }

    // MARK: - Key press helper

    private static func pressKey(_ code: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let src else { return }
        if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.02)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - App Expose via Dock AX

    private static func triggerAppExpose() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else { return }

        guard let dockApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return
        }
        let dockAX = AXUIElementCreateApplication(dockApps.processIdentifier)

        if let item = findDockItemByName(dockAX, name: appName, action: "AXShowExpose") {
            AXUIElementPerformAction(item, "AXShowExpose" as CFString)
            return
        }

        // Fall back to any dock item with AXShowExpose
        if let item = findDockItemWithAction(dockAX, action: "AXShowExpose") {
            AXUIElementPerformAction(item, "AXShowExpose" as CFString)
        }
    }

    private static func findDockItemWithAction(_ element: AXUIElement, action: String) -> AXUIElement? {
        var actionsRef: CFArray?
        AXUIElementCopyActionNames(element, &actionsRef)
        if let actions = actionsRef as? [String], actions.contains(action) {
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            if roleRef as? String == "AXDockItem" {
                return element
            }
        }
        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findDockItemWithAction(child, action: action) { return found }
            }
        }
        return nil
    }

    private static func findDockItemByName(_ element: AXUIElement, name: String, action: String) -> AXUIElement? {
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if titleRef as? String == name {
            var actionsRef: CFArray?
            AXUIElementCopyActionNames(element, &actionsRef)
            if let actions = actionsRef as? [String], actions.contains(action) {
                return element
            }
        }
        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findDockItemByName(child, name: name, action: action) { return found }
            }
        }
        return nil
    }

    // MARK: - Media keys (NX system-defined events)

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
                subtype: 8,
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

// MARK: - NX key type constants

private let NX_KEYTYPE_SOUND_UP:   Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_MUTE:       Int32 = 7
private let NX_KEYTYPE_PLAY:       Int32 = 16
private let NX_KEYTYPE_NEXT:       Int32 = 17
private let NX_KEYTYPE_PREVIOUS:   Int32 = 18
