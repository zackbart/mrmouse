import Foundation

public struct MrMouseConfig: Codable, Equatable {
    public var devices: [String: DeviceConfig]  // keyed by serial number or product name
    public var globalProfile: Profile
    public var appProfiles: [String: Profile]    // keyed by bundle identifier
    public var launchAtLogin: Bool

    public init(
        devices: [String: DeviceConfig] = [:],
        globalProfile: Profile = .default,
        appProfiles: [String: Profile] = [:],
        launchAtLogin: Bool = false
    ) {
        self.devices = devices
        self.globalProfile = globalProfile
        self.appProfiles = appProfiles
        self.launchAtLogin = launchAtLogin
    }
}

public struct DeviceConfig: Codable, Equatable {
    public var dpi: Int
    public var smartShiftEnabled: Bool
    public var smartShiftThreshold: Int  // 1-255, higher = harder to trigger free-spin
    public var hiResScrollEnabled: Bool
    public var scrollInverted: Bool
    public var thumbWheelInverted: Bool

    public init(
        dpi: Int = 1000,
        smartShiftEnabled: Bool = true,
        smartShiftThreshold: Int = 30,
        hiResScrollEnabled: Bool = true,
        scrollInverted: Bool = false,
        thumbWheelInverted: Bool = false
    ) {
        self.dpi = dpi
        self.smartShiftEnabled = smartShiftEnabled
        self.smartShiftThreshold = smartShiftThreshold
        self.hiResScrollEnabled = hiResScrollEnabled
        self.scrollInverted = scrollInverted
        self.thumbWheelInverted = thumbWheelInverted
    }
}

public struct Profile: Codable, Equatable {
    public var buttonMappings: [ButtonMapping]
    public var gestureActions: GestureActions

    public init(
        buttonMappings: [ButtonMapping] = ButtonMapping.defaults,
        gestureActions: GestureActions = .default
    ) {
        self.buttonMappings = buttonMappings
        self.gestureActions = gestureActions
    }

    public static let `default` = Profile()
}

public struct ButtonMapping: Codable, Equatable {
    public var controlID: UInt16       // HID++ control ID
    public var action: ButtonAction
    public var diverted: Bool          // whether to divert from standard HID

    public init(controlID: UInt16, action: ButtonAction, diverted: Bool = false) {
        self.controlID = controlID
        self.action = action
        self.diverted = diverted
    }

    public static let defaults: [ButtonMapping] = [
        ButtonMapping(controlID: 0x0050, action: .default),  // Left
        ButtonMapping(controlID: 0x0051, action: .default),  // Right
        ButtonMapping(controlID: 0x0052, action: .default),  // Middle
        ButtonMapping(controlID: 0x0053, action: .default),  // Back
        ButtonMapping(controlID: 0x0056, action: .default),  // Forward
        ButtonMapping(controlID: 0x00C3, action: .gestureButton, diverted: true),  // Gesture
    ]
}

public enum ButtonAction: Codable, Equatable {
    case `default`                     // pass through to OS
    case keyboardShortcut(KeyCombo)
    case gestureButton                 // handle as gesture (tap + swipe directions)
    case disabled
    case openApp(bundleID: String)
    case systemAction(SystemAction)
}

public struct KeyCombo: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public struct Modifiers: OptionSet, Codable, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option  = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift   = Modifiers(rawValue: 1 << 3)
    }

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum SystemAction: String, Codable {
    case missionControl = "mission_control"
    case appExpose = "app_expose"
    case switchDesktopLeft = "switch_desktop_left"
    case switchDesktopRight = "switch_desktop_right"
    case launchpad = "launchpad"
    case showDesktop = "show_desktop"
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case mute = "mute"
    case playPause = "play_pause"
    case nextTrack = "next_track"
    case prevTrack = "prev_track"
    case screenshot = "screenshot"
    case spotlight = "spotlight"
    case lockScreen = "lock_screen"
}

public struct GestureActions: Codable, Equatable {
    public var tap: ButtonAction
    public var swipeUp: ButtonAction
    public var swipeDown: ButtonAction
    public var swipeLeft: ButtonAction
    public var swipeRight: ButtonAction

    public init(
        tap: ButtonAction = .systemAction(.missionControl),
        swipeUp: ButtonAction = .systemAction(.missionControl),
        swipeDown: ButtonAction = .systemAction(.appExpose),
        swipeLeft: ButtonAction = .systemAction(.switchDesktopLeft),
        swipeRight: ButtonAction = .systemAction(.switchDesktopRight)
    ) {
        self.tap = tap
        self.swipeUp = swipeUp
        self.swipeDown = swipeDown
        self.swipeLeft = swipeLeft
        self.swipeRight = swipeRight
    }

    public static let `default` = GestureActions()
}
