import CoreGraphics
import Foundation

/// The set of gestures the recognizer can classify.
public enum GestureType: Equatable {
    case tap
    case swipeUp
    case swipeDown
    case swipeLeft
    case swipeRight
}

/// Tracks gesture-button state and classifies the motion as a gesture when the
/// button is released.
///
/// Usage:
/// 1. Feed button down/up events via `buttonDown()` / `buttonUp()`.
/// 2. While the button is held, feed mouse-move deltas via `addDelta(dx:dy:)`.
/// 3. On button-up the recognizer classifies the accumulated motion and fires
///    `onGesture` with the result.
///
/// All methods must be called from the main actor.
@MainActor
public final class GestureRecognizer {

    // MARK: - Configuration

    /// Minimum displacement (in points) along the dominant axis to count as a
    /// swipe rather than a tap.
    public var minSwipeDistance: CGFloat

    // MARK: - Callbacks

    /// Called on button-up with the classified gesture.
    public var onGesture: ((GestureType) -> Void)?

    // MARK: - Private state

    private var isPressed = false
    private var accumulatedDX: CGFloat = 0
    private var accumulatedDY: CGFloat = 0
    private var skipNextDelta = false

    // MARK: - Init

    public init(minSwipeDistance: CGFloat = 30) {
        self.minSwipeDistance = minSwipeDistance
    }

    // MARK: - Input

    /// Call when the gesture button is pressed.
    public func buttonDown() {
        isPressed = true
        accumulatedDX = 0
        accumulatedDY = 0
        skipNextDelta = true
    }

    /// Call when the gesture button is released. Fires `onGesture` synchronously.
    public func buttonUp() {
        guard isPressed else { return }
        isPressed = false
        skipNextDelta = false
        let gesture = classify(dx: accumulatedDX, dy: accumulatedDY)
        onGesture?(gesture)
    }

    /// Feed a mouse-movement delta. Always accumulates — `buttonDown()` resets
    /// the counters so only movement since the last press is classified.
    /// The first delta after a button-down is skipped to avoid the initial
    /// movement spike that occurs when the thumb button is pressed.
    public func addDelta(dx: CGFloat, dy: CGFloat) {
        if skipNextDelta {
            skipNextDelta = false
            return
        }
        accumulatedDX += dx
        accumulatedDY += dy
    }

    // MARK: - Classification

    private func classify(dx: CGFloat, dy: CGFloat) -> GestureType {
        let absX = abs(dx)
        let absY = abs(dy)

        // If neither axis exceeds the threshold it's a tap
        guard absX >= minSwipeDistance || absY >= minSwipeDistance else {
            return .tap
        }

        // Dominant axis determines swipe direction
        if absX >= absY {
            return dx > 0 ? .swipeRight : .swipeLeft
        } else {
            // Screen Y increases downward in CoreGraphics
            return dy > 0 ? .swipeDown : .swipeUp
        }
    }
}
