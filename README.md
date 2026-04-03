# MrMouse

Lightweight macOS driver for Logitech MX Master 3S, replacing Logi Options+.

## Current Status

### Working

**Gesture button detection via CGEventTap:**
- Gesture button (thumb button) on MX Master 3S generates CGEvent button 5 through the standard HID mouse interface
- `EventTapManager` intercepts button 5 press/release events
- Button 5 events are routed to `GestureRecognizer` (press → accumulate motion → release → classify)
- Gesture types recognized: `tap`, `swipeUp`, `swipeDown`, `swipeLeft`, `swipeRight`
- System Mission Control trigger from button 5 is suppressed (prevents default behavior)

**Action dispatch via virtual key codes (macOS 26 Tahoe):**
- **Mission Control** — key code 160 (verified working)
- **App Exposé** — `AXShowExpose` on the frontmost app's Dock `AXDockItem` via Accessibility API
- **Show Desktop** — key code 103
- **Launchpad** — key code 131
- **Spotlight, Screenshot, Lock Screen** — keyboard shortcuts via CGEvent (no modifiers)
- **Volume/Media keys** — `NSEvent.otherEvent` with `NSSystemDefined` subtype

**HID++ protocol over Bolt receiver:**
- Device discovery, feature enumeration (33 features), gesture button diversion via `SetControlReporting`
- Bolt receiver works for init/response but does NOT forward unsolicited device notifications on the vendor interface — macOS kernel blocks them
- `kIOHIDOptionsTypeSeizeDevice` was tested — same result
- HID++ notifications are NOT needed for gesture button — we use CGEventTap instead

**BLETransport (partially implemented):**
- CoreBluetooth-based transport in `BLETransport.swift`
- Scans for Logitech devices by name, discovers GATT service
- When mouse is paired via macOS Bluetooth, CoreBluetooth can't connect (system owns the GATT connection)
- BLE path exists but is not the primary working path

### Not Working

**Desktop switching (Ctrl+Left/Right arrows):**
- CGEvent modifier flags (`.maskControl`, `.maskCommand`) are **not recognized by the system** on macOS 26 Tahoe
- Separate Ctrl key press/release via CGEvent also does not work
- `SLSShowSpaces` and `CGSShowSpaces` in SkyLight framework return errors
- `CGSManagedDisplaySetCurrentSpace` crashes
- **This is a known macOS 26 system-level bug** — even [yabai](https://github.com/koekeishiya/yabai/issues/2699) and [Logi Options+](https://www.reddit.com/r/logitech/comments/1q4fisd/) are broken for desktop switching on Tahoe

**What doesn't work (attempted and rejected):**
- `CoreDockSendNotification` — `Dock.framework` does not exist on macOS 26 (moved to `WindowManager.framework`, no public API)
- `DistributedNotificationCenter` (`com.apple.expose.awake`, etc.) — posts succeed but Dock ignores them
- AX actions on Dock app element — all return `kAXErrorActionUnsupported` (-25206)
- `CGWarpMouseCursorPosition` for hot corners — synthetic mouse events don't trigger hot corners
- CGEvent keyboard events via `cgSessionEventTap` — same limitation as `cghidEventTap`

## Architecture

```
mrmouse/mrmouse/
  HIDPPCore/
    Transport/
      HIDTransport.swift       - IOKit HID (Bolt receiver)
      HIDTransportProtocol.swift
      BLETransport.swift       - CoreBluetooth (experimental)
    Protocol/
      HIDPPMessage.swift       - HID++ 2.0 message format
      HIDPPError.swift
    Device/
      HIDPPDevice.swift        - Feature discovery, request-response
      ReceiverEnumerator.swift
    Features/
      ReprogControls.swift     - Button diversion (0x00C3)
      AdjustableDPI.swift
      SmartShift.swift
      UnifiedBattery.swift
      FeatureRegistry.swift
  EventEngine/
    GestureRecognizer.swift    - Classify thumb button + motion
    EventTapManager.swift      - CGEventTap (receives button 5)
    ActionDispatcher.swift     - Execute actions (key codes + AX)
    AppProfileManager.swift    - Per-app profiles
  Config/
    ConfigManager.swift        - JSON persistence
    ConfigModels.swift         - Config structs
    DefaultConfig.swift        - Default gesture mappings
  AppState.swift               - Central coordinator
  MrMouseApp.swift             - SwiftUI menu bar app
  SettingsWindow.swift         - Gesture + Button mapping settings
  Views/
    ButtonMappingView.swift    - Per-button action picker
```

## Key Technical Findings

### Gesture button mechanism
- The MX Master 3S gesture button sends standard CGEvent `otherMouseDown`/`otherMouseUp` with button number 5
- This works through the standard HID mouse interface (usagePage 0x0001) — no HID++ needed
- The CGEventTap intercepts these events and suppresses them before the system can trigger Mission Control
- Mouse movement deltas between press/release are accumulated for swipe classification

### macOS 26 Tahoe virtual key codes
System UI functions that bypass the CGEvent modifier flag limitation:

| Function | Key Code | Method |
|---|---|---|
| Mission Control | 160 | CGEvent keyboardEvent |
| Show Desktop | 103 | CGEvent keyboardEvent |
| Launchpad | 131 | CGEvent keyboardEvent |
| Emoji Picker | 179 | CGEvent keyboardEvent |
| App Exposé | N/A | AXShowExpose on Dock AXDockItem |
| Volume/Media | N/A | NSSystemDefined NSEvent |
| Desktop Switch | — | **Broken on Tahoe** |

### Why HID++ notifications don't work
- macOS kernel HID driver blocks unsolicited vendor-defined HID++ notifications from USB receivers
- `setControlReporting` succeeds (device accepts diversion) but notifications never arrive at user-space
- `kIOHIDOptionsTypeSeizeDevice` doesn't bypass this — same result

### Why Dock.framework / CoreDockSendNotification doesn't work
- `Dock.framework` (`/System/Library/PrivateFrameworks/Dock.framework/`) was removed in macOS 26
- The Dock binary now lives at `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock`
- Mission Control logic moved to `WindowManager.framework` (Swift-only, no public API)
- The Dock's internal `enterExitMissionControl` selector is not accessible from other processes

### Logi Options+ status on macOS 26
- Logi Options+ is [broken on Tahoe](https://www.reddit.com/r/logitech/comments/1q4fisd/) — loading screen stuck, features broken
- Logitech [released a fix in Jan 2026](https://www.logitech.com/blog/2026/01/07/restoring-access-to-options-and-g-hub-on-macos/) but desktop switching likely still broken (same OS limitation)
- Logi Options+ uses Apple-entitled kernel extensions / DriverKit for some features — not available to third-party apps

## Building

Open `mrmouse/mrmouse.xcodeproj` in Xcode and build the `mrmouse` scheme. Requires macOS 26+ (Tahoe).

### Permissions needed
- **Accessibility** — for CGEventTap (mouse event interception) and AXShowExpose
- **Bluetooth** — for BLETransport (Info.plist keys already added)

## Next Steps

1. **Desktop switching** — monitor macOS updates for a fix; may become possible if Apple restores CGEvent modifier support or provides a new API
2. **Remove debug logging** — clean up verbose per-report logging in HIDTransport and HIDPPDevice
3. **BLE transport** — complete if Bolt receiver path is undesirable
4. **Remove dead code** — DPI, scroll, and profile views are no longer in the UI but files still exist
