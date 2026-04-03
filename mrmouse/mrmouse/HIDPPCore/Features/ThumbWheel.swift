import Foundation

// MARK: - ThumbWheel (Feature ID: 0x2150)
//
// Controls the horizontal thumb wheel on MX Master devices.
// Param byte layout: [flags]
//   Bit 0: inverted  (1 = inverted scroll direction)
//   Bit 1: diverted  (1 = deliver events via HID++ notifications)

// MARK: - Data Model

/// Configuration for the horizontal thumb wheel.
public struct ThumbWheelConfig: Equatable {
    /// When true the scroll direction is inverted.
    public var inverted: Bool
    /// When true thumb wheel events are delivered via HID++ notifications
    /// instead of standard HID horizontal scroll reports.
    public var diverted: Bool

    public init(inverted: Bool, diverted: Bool) {
        self.inverted = inverted
        self.diverted = diverted
    }

    // MARK: Bit packing

    /// Construct config from the raw flags byte returned by the device.
    public init(flagsByte: UInt8) {
        inverted = (flagsByte & 0x01) != 0
        diverted = (flagsByte & 0x02) != 0
    }

    /// The packed flags byte to send to the device.
    public var flagsByte: UInt8 {
        var byte: UInt8 = 0
        if inverted { byte |= 0x01 }
        if diverted { byte |= 0x02 }
        return byte
    }
}

// MARK: - Feature Module

public enum ThumbWheel {

    /// Returns the current thumb wheel configuration.
    /// Function 0x00 — GetThumbWheelConfig.
    public static func getConfig(device: HIDPPDevice) throws -> ThumbWheelConfig {
        let idx = try FeatureRegistry.index(for: .thumbWheel, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        // Response: [flags, ...]
        guard response.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        return ThumbWheelConfig(flagsByte: response.parameters[0])
    }

    /// Writes a new thumb wheel configuration to the device.
    /// Function 0x01 — SetThumbWheelConfig.
    public static func setConfig(device: HIDPPDevice, config: ThumbWheelConfig) throws {
        let idx = try FeatureRegistry.index(for: .thumbWheel, on: device)
        let params = Data([config.flagsByte])
        _ = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)
    }
}
