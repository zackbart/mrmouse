import CoreGraphics
import CoreFoundation
import Foundation

/// Manages a CGEventTap that intercepts extra mouse button events.
///
/// The callback is a C function and must be fast — it looks up the button
/// number and dispatches to `buttonHandler` asynchronously so HID++ work
/// never blocks the event tap.
public final class EventTapManager {

    // MARK: - Public interface

    /// Called on every other-mouse down/up event.
    /// - Parameters:
    ///   - Int: button number (2 = middle, 3 = back, 4 = forward, …)
    ///   - Bool: true = button down, false = button up
    /// - Returns: the event to pass through, or nil to suppress it
    public var buttonHandler: ((Int, Bool) -> CGEvent?)?

    // MARK: - Private state

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Init / deinit

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Creates and activates the event tap. Must be called from the main thread.
    public func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let selfPtr = Unmanaged.passRetained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPtr.toOpaque()
        ) else {
            // Release the retained reference if tap creation fails
            selfPtr.release()
            print("[EventTapManager] Failed to create event tap — Accessibility permission required")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Disables and tears down the event tap.
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Internal re-enable (called from C callback)

    /// Called when macOS disables the tap (e.g. due to slow handling).
    fileprivate func handleTapDisabled() {
        guard let tap = eventTap else { return }
        print("[EventTapManager] Event tap was disabled by macOS — re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Synchronous callback dispatch

    /// Invoked synchronously on the run loop thread — must return quickly.
    fileprivate func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let isDown = (type == .otherMouseDown)

        // Fast path: no handler → pass through
        guard let handler = buttonHandler else {
            return Unmanaged.passRetained(event)
        }

        // The handler may post key events or do quick lookups — it must itself
        // be non-blocking. Heavy work (HID++ calls) should be dispatched inside
        // the handler onto a background queue.
        if let result = handler(buttonNumber, isDown) {
            return Unmanaged.passRetained(result)
        } else {
            // Returning nil suppresses the event
            return nil
        }
    }
}

// MARK: - C callback

/// Top-level C function required by CGEventTapCreate.
/// Bridges into the EventTapManager instance via the userInfo pointer.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(ptr).takeUnretainedValue()

    // macOS disables taps that are too slow; re-enable immediately.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        manager.handleTapDisabled()
        return Unmanaged.passRetained(event)
    }

    return manager.handleEvent(type: type, event: event)
}
