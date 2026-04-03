import ApplicationServices
import CoreGraphics
import Foundation

/// Switches desktops using CGSHideSpaces/CGSShowSpaces private CGS APIs.
///
/// On macOS 26 (Tahoe), CGSSetCurrentDesktop has been removed, and
/// CGEvent modifier flags are stripped by the WindowServer.
/// But CGSHideSpaces and CGSShowSpaces still exist in SkyLight.framework.
public enum DesktopSwitcher {

    public enum Direction {
        case left
        case right
    }

    // MARK: - CGS function pointers (loaded at runtime)

    private typealias CGSFn = @convention(c) () -> Int32
    private typealias CGSGetActiveSpaceFn = @convention(c) (Int32) -> UInt64
    private typealias CGSCopyManagedDisplaySpacesFn = @convention(c) (Int32, CFString?) -> CFArray?
    private typealias CGSSpacesFn = @convention(c) (Int32, CFArray) -> Int32

    private static let skyLight: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    }()

    private static func loadFn<T>(_ name: String) -> T? {
        guard let handle = skyLight, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let pCGSMainConnectionID: CGSFn? = loadFn("CGSMainConnectionID")
    private static let pCGSGetActiveSpace: CGSGetActiveSpaceFn? = loadFn("CGSGetActiveSpace")
    private static let pCGSCopyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFn? = loadFn("CGSCopyManagedDisplaySpaces")
    private static let pCGSShowSpaces: CGSSpacesFn? = loadFn("CGSShowSpaces")
    private static let pCGSHideSpaces: CGSSpacesFn? = loadFn("CGSHideSpaces")

    // MARK: - Public API

    @discardableResult
    public static func switchDesktop(_ direction: Direction) -> Bool {
        guard let cid = pCGSMainConnectionID?(),
              cid != 0,
              let activeSpace = pCGSGetActiveSpace?(cid),
              activeSpace != 0,
              let showSpaces = pCGSShowSpaces,
              let hideSpaces = pCGSHideSpaces,
              let displays = pCGSCopyManagedDisplaySpaces?(cid, nil),
              CFArrayGetCount(displays) > 0,
              let firstDisplay = CFArrayGetValueAtIndex(displays, 0) else {
            NSLog("[DesktopSwitcher] Failed to load CGS functions or get space info")
            return false
        }

        let display = unsafeBitCast(firstDisplay, to: NSDictionary.self)
        guard let spaces = display["Spaces"] as? NSArray else { return false }

        // Find active space index
        var activeIndex = -1
        for (i, space) in spaces.enumerated() {
            guard let spaceDict = space as? NSDictionary,
                  let id64 = spaceDict["id64"] as? Int64 else { continue }
            if UInt64(bitPattern: id64) == activeSpace {
                activeIndex = i
                break
            }
        }

        guard activeIndex >= 0 else { return false }

        let targetIndex = direction == .right ? activeIndex + 1 : activeIndex - 1
        guard targetIndex >= 0, targetIndex < spaces.count else {
            NSLog("[DesktopSwitcher] At edge, can't switch %@",
                  direction == .right ? "right" : "left")
            return false
        }

        guard let targetSpace = spaces[targetIndex] as? NSDictionary,
              let targetID64 = targetSpace["id64"] as? Int64 else { return false }

        NSLog("[DesktopSwitcher] Switching: space %llu -> %lld",
              activeSpace, targetID64)

        // Create CFNumbers for space IDs
        var activeVal = activeSpace
        var targetVal = targetID64
        let activeNum = CFNumberCreate(kCFAllocatorDefault, .longLongType, &activeVal)
        let targetNum = CFNumberCreate(kCFAllocatorDefault, .longLongType, &targetVal)
        guard let activeNum, let targetNum else { return false }

        // Hide current space, show target space
        let hideArr = NSMutableArray()
        hideArr.add(activeNum)
        let showArr = NSMutableArray()
        showArr.add(targetNum)
        let hideCF = hideArr as CFArray
        let showCF = showArr as CFArray

        let hErr = hideSpaces(cid, hideCF)
        NSLog("[DesktopSwitcher] CGSHideSpaces returned %d", hErr)

        Thread.sleep(forTimeInterval: 0.05)

        let sErr = showSpaces(cid, showCF)
        NSLog("[DesktopSwitcher] CGSShowSpaces returned %d", sErr)

        Thread.sleep(forTimeInterval: 0.3)

        // Verify
        if let newActive = pCGSGetActiveSpace?(cid) {
            NSLog("[DesktopSwitcher] Active space is now: %llu (was: %llu)", newActive, activeSpace)
            return newActive != activeSpace
        }

        return true
    }

    /// Returns true if there's a desktop to switch to in the given direction.
    public static func canSwitch(_ direction: Direction) -> Bool {
        guard let info = getSpaceInfo() else { return true }
        return !shouldBlockSwitch(info: info, direction: direction)
    }

    // MARK: - Space info (public for other uses)

    public struct SpaceInfo {
        public let spaceCount: Int
        public let currentIndex: Int
    }

    public static func getSpaceInfo() -> SpaceInfo? {
        guard let cid = pCGSMainConnectionID?(), cid != 0,
              let activeSpace = pCGSGetActiveSpace?(cid),
              activeSpace != 0,
              let displays = pCGSCopyManagedDisplaySpaces?(cid, nil),
              CFArrayGetCount(displays) > 0,
              let firstDisplay = CFArrayGetValueAtIndex(displays, 0) else { return nil }

        let display = unsafeBitCast(firstDisplay, to: NSDictionary.self)
        guard let spaces = display["Spaces"] as? NSArray else { return nil }

        var targetActiveSpace = activeSpace
        if let currentSpace = display["Current Space"] as? NSDictionary,
           let id64 = currentSpace["id64"] as? Int64, id64 != 0 {
            targetActiveSpace = UInt64(bitPattern: id64)
        }

        var totalSpaces = 0
        var activeIndex = 0
        var foundActive = false

        for space in spaces {
            guard let spaceDict = space as? NSDictionary,
                  let id64 = spaceDict["id64"] as? Int64 else { continue }
            if !foundActive && UInt64(bitPattern: id64) == targetActiveSpace {
                activeIndex = totalSpaces
                foundActive = true
            }
            totalSpaces += 1
        }

        guard totalSpaces > 0, foundActive else { return nil }
        return SpaceInfo(spaceCount: totalSpaces, currentIndex: activeIndex)
    }

    private static func shouldBlockSwitch(info: SpaceInfo, direction: Direction) -> Bool {
        switch direction {
        case .left:  return info.currentIndex == 0
        case .right: return info.currentIndex + 1 >= info.spaceCount
        }
    }
}
