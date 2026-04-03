import AppKit
import Foundation

/// Observes NSWorkspace for foreground-application changes and maintains the
/// current bundle identifier.  Zero CPU cost when apps are not switching.
public final class AppProfileManager {

    // MARK: - Public interface

    /// The bundle identifier of the currently active application, or nil if
    /// it cannot be determined.
    public private(set) var currentBundleID: String?

    /// Called whenever the foreground application changes.
    /// The parameter is the new bundle identifier (may be nil).
    public var onAppChanged: ((String?) -> Void)?

    // MARK: - Private state

    private var observer: NSObjectProtocol?

    // MARK: - Init / deinit

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Starts observing workspace notifications. Safe to call multiple times.
    public func start() {
        guard observer == nil else { return }

        // Seed the current value immediately
        currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            self.currentBundleID = bundleID
            self.onAppChanged?(bundleID)
        }
    }

    /// Stops observing. Safe to call even if `start()` was never called.
    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
