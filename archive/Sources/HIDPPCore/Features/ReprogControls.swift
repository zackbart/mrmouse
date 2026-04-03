import Foundation

// MARK: - ReprogControls (Feature ID: 0x1B04)
//
// ReprogControlsV4 — button remapping and diversion for extra mouse buttons.
// Diverting a button causes its press/release to be delivered as HID++
// notifications rather than standard HID events, enabling custom handling
// (e.g. gesture detection on the gesture button).

// MARK: - Data Models

/// Static information about a single remappable control.
public struct ControlInfo: Equatable {
    /// Stable hardware control identifier.
    public var controlID: UInt16
    /// Default task (logical function) assigned to this control.
    public var taskID: UInt16
    /// Capability flags (see Logitech spec).
    public var flags: UInt16
    /// Physical position index.
    public var position: UInt8
    /// Control group (for mutual-exclusion rules).
    public var group: UInt8
    /// Group mask.
    public var groupMask: UInt8

    public init(controlID: UInt16, taskID: UInt16, flags: UInt16,
                position: UInt8, group: UInt8, groupMask: UInt8) {
        self.controlID = controlID
        self.taskID    = taskID
        self.flags     = flags
        self.position  = position
        self.group     = group
        self.groupMask = groupMask
    }
}

// MARK: ControlReporting flags

/// Bitmask flags that govern how a control's events are reported.
public struct ControlReportingFlags: OptionSet, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Divert button — deliver events via HID++ notifications instead of HID.
    public static let divert   = ControlReportingFlags(rawValue: 0x01)
    /// Persist diversion across power cycles.
    public static let persist  = ControlReportingFlags(rawValue: 0x02)
    /// Also deliver raw (X, Y) pointer deltas via HID++ while button is held.
    public static let rawXY    = ControlReportingFlags(rawValue: 0x04)
    /// Force the button into its "force" gesture mode.
    public static let force    = ControlReportingFlags(rawValue: 0x08)
}

/// The current reporting configuration for a single control.
public struct ControlReporting: Equatable {
    /// Target task / control ID the button is remapped to (0 = default).
    public var remapped: UInt16
    /// Reporting mode flags.
    public var flags: ControlReportingFlags

    public init(remapped: UInt16, flags: ControlReportingFlags) {
        self.remapped = remapped
        self.flags    = flags
    }
}

// MARK: - Feature Module

public enum ReprogControls {

    /// Returns the total number of remappable controls on the device.
    /// Function 0x00 — GetControlCount.
    public static func getControlCount(device: HIDPPDevice) throws -> Int {
        let idx = try FeatureRegistry.index(for: .reprogControlsV4, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        guard response.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        return Int(response.parameters[0])
    }

    /// Returns the static description of the control at the given index.
    /// Function 0x01 — GetControlInfo.
    ///
    /// - Parameter index: Zero-based position in the control table.
    public static func getControlInfo(device: HIDPPDevice, index: Int) throws -> ControlInfo {
        let idx = try FeatureRegistry.index(for: .reprogControlsV4, on: device)
        let params = Data([UInt8(index)])
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)
        // Response layout (byte offsets within parameters):
        //   0-1: controlID (big-endian)
        //   2-3: taskID    (big-endian)
        //   4-5: flags     (big-endian)
        //   6:   position
        //   7:   group
        //   8:   groupMask
        guard response.parameters.count >= 9 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let p = response.parameters
        let controlID = UInt16(p[0]) << 8 | UInt16(p[1])
        let taskID    = UInt16(p[2]) << 8 | UInt16(p[3])
        let flags     = UInt16(p[4]) << 8 | UInt16(p[5])
        return ControlInfo(
            controlID: controlID,
            taskID:    taskID,
            flags:     flags,
            position:  p[6],
            group:     p[7],
            groupMask: p[8]
        )
    }

    /// Returns the current reporting configuration for a control by its hardware ID.
    /// Function 0x02 — GetControlReporting.
    ///
    /// - Parameter controlID: The hardware control identifier from `ControlInfo.controlID`.
    public static func getControlReporting(device: HIDPPDevice, controlID: UInt16) throws -> ControlReporting {
        let idx = try FeatureRegistry.index(for: .reprogControlsV4, on: device)
        let idHi = UInt8((controlID >> 8) & 0xFF)
        let idLo = UInt8(controlID & 0xFF)
        let params = Data([idHi, idLo])
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x02, parameters: params)
        // Response layout:
        //   0-1: controlID echo
        //   2-3: remapped taskID (big-endian)
        //   4:   reporting flags
        guard response.parameters.count >= 5 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let p = response.parameters
        let remapped = UInt16(p[2]) << 8 | UInt16(p[3])
        let flags    = ControlReportingFlags(rawValue: p[4])
        return ControlReporting(remapped: remapped, flags: flags)
    }

    /// Writes a new reporting configuration for a control.
    /// Function 0x03 — SetControlReporting.
    ///
    /// To intercept button events via HID++ notifications, set `.divert` in
    /// `reporting.flags`. Optionally add `.persist` to survive reboots, and
    /// `.rawXY` to also receive pointer deltas while the button is held.
    ///
    /// - Parameters:
    ///   - controlID: The hardware control identifier.
    ///   - reporting: The desired reporting configuration.
    public static func setControlReporting(device: HIDPPDevice, controlID: UInt16, reporting: ControlReporting) throws {
        let idx = try FeatureRegistry.index(for: .reprogControlsV4, on: device)
        let idHi = UInt8((controlID >> 8) & 0xFF)
        let idLo = UInt8(controlID & 0xFF)
        let remapHi = UInt8((reporting.remapped >> 8) & 0xFF)
        let remapLo = UInt8(reporting.remapped & 0xFF)
        let params = Data([idHi, idLo, remapHi, remapLo, reporting.flags.rawValue])
        _ = try device.featureRequest(featureIndex: idx, functionID: 0x03, parameters: params)
    }
}
