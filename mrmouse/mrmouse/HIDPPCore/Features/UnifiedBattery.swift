import Foundation

// MARK: - UnifiedBattery (Feature ID: 0x1004)
//
// Reads battery status from devices that implement the Unified Battery feature.
// The same feature index / function 0x00 is used both for polling and as the
// notification that the device pushes when battery state changes.

// MARK: - Data Models

/// Coarse battery level reported alongside the percentage.
public enum BatteryLevel: UInt8 {
    case critical = 1
    case low      = 2
    case good     = 4
    case full     = 8

    /// Human-readable label.
    public var description: String {
        switch self {
        case .critical: return "Critical"
        case .low:      return "Low"
        case .good:     return "Good"
        case .full:     return "Full"
        }
    }
}

/// Current battery status for the device.
public struct BatteryStatus: Equatable {
    /// State-of-charge in whole percent (0–100).  Some devices report 0 when
    /// discharging below the minimum measurable threshold.
    public var percentage: Int
    /// Coarse battery level (matches the level flags in the HID++ response).
    public var level: BatteryLevel?
    /// Whether the device is currently being charged.
    public var charging: Bool

    public init(percentage: Int, level: BatteryLevel?, charging: Bool) {
        self.percentage = percentage
        self.level      = level
        self.charging   = charging
    }
}

// MARK: - Feature Module

public enum UnifiedBattery {

    /// Queries the device for its current battery status.
    /// Function 0x00 — GetBatteryStatus.
    ///
    /// The device also pushes this same function (0x00) as an unsolicited
    /// notification when the battery level changes; callers should parse
    /// incoming `HIDPPMessage` objects with `parse(notification:)`.
    public static func getStatus(device: HIDPPDevice) throws -> BatteryStatus {
        let idx = try FeatureRegistry.index(for: .unifiedBattery, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        return try parse(parameters: response.parameters)
    }

    /// Parses a battery status notification or poll response.
    ///
    /// Call this from your `device.onNotification` handler when
    /// `message.featureIndex` matches the UnifiedBattery feature index.
    ///
    /// - Parameter notification: An incoming HID++ message from the device.
    /// - Returns: The parsed battery status, or nil if the message is not a
    ///            battery status report.
    public static func parse(notification: HIDPPMessage) -> BatteryStatus? {
        // Notifications use function 0 (same as the poll response)
        guard notification.functionID == 0x00 else { return nil }
        return try? parse(parameters: notification.parameters)
    }

    // MARK: - Private Helpers

    /// Decodes the parameter bytes that appear in both poll responses and push notifications.
    ///
    /// Protocol layout:
    ///   [0] percentage (0–100)
    ///   [1] battery level bitmask (critical=1, low=2, good=4, full=8)
    ///   [2] charging status flags (bit 0 = charging)
    private static func parse(parameters: Data) throws -> BatteryStatus {
        guard parameters.count >= 3 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let percentage   = Int(parameters[0])
        let levelRaw     = parameters[1]
        let chargingByte = parameters[2]

        // The level field is a bitmask; pick the highest set bit.
        let level = BatteryLevel(rawValue: levelRaw)
        let charging = (chargingByte & 0x01) != 0

        return BatteryStatus(percentage: percentage, level: level, charging: charging)
    }
}
