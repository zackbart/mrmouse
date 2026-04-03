import Foundation

// MARK: - SmartShift (Feature ID: 0x2110)
//
// Controls the SmartShift ratchet/free-spin wheel behaviour.
// Param byte layout: [enabled (0x00 / 0x01), threshold (1–255)]

// MARK: - Data Model

/// Configuration for the SmartShift ratchet mechanism.
public struct SmartShiftConfig: Equatable {
    /// Whether SmartShift is active (auto-switches between ratchet and free-spin).
    public var enabled: Bool
    /// Threshold torque at which the wheel auto-disengages the ratchet (1–255).
    public var autoDisengageThreshold: UInt8

    public init(enabled: Bool, autoDisengageThreshold: UInt8) {
        self.enabled = enabled
        self.autoDisengageThreshold = autoDisengageThreshold
    }
}

// MARK: - Feature Module

public enum SmartShift {

    /// Returns the current SmartShift configuration.
    /// Function 0x00 — GetSmartShift.
    public static func getConfig(device: HIDPPDevice) throws -> SmartShiftConfig {
        let idx = try FeatureRegistry.index(for: .smartShift, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        // Response: [enabled, threshold, ...]
        guard response.parameters.count >= 2 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let enabled   = response.parameters[0] != 0x00
        let threshold = response.parameters[1]
        return SmartShiftConfig(enabled: enabled, autoDisengageThreshold: threshold)
    }

    /// Writes a new SmartShift configuration to the device.
    /// Function 0x01 — SetSmartShift.
    public static func setConfig(device: HIDPPDevice, config: SmartShiftConfig) throws {
        let idx = try FeatureRegistry.index(for: .smartShift, on: device)
        let enabledByte: UInt8 = config.enabled ? 0x01 : 0x00
        let params = Data([enabledByte, config.autoDisengageThreshold])
        _ = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)
    }
}
