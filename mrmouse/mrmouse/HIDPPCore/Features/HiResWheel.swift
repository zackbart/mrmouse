import Foundation

// MARK: - HiResWheel (Feature ID: 0x2121)
//
// Controls high-resolution wheel mode, inversion, and HID target routing.
// Mode flags are packed into a single byte:
//   Bit 4: hiRes   (1 = high-resolution, 0 = standard)
//   Bit 3: invert  (1 = inverted scroll direction)
//   Bit 2: target  (1 = HID++ notifications, 0 = standard HID)

// MARK: - Data Models

/// The current operating mode of the scroll wheel.
public struct HiResWheelMode: Equatable {
    /// When true the wheel sends fine-grained (high-resolution) scroll events.
    public var hiRes: Bool
    /// When true scroll direction is inverted.
    public var invert: Bool
    /// When true scroll events are delivered via HID++ notifications instead of standard HID.
    public var target: Bool

    public init(hiRes: Bool, invert: Bool, target: Bool) {
        self.hiRes  = hiRes
        self.invert = invert
        self.target = target
    }

    // MARK: Bit packing

    /// Construct a mode from the raw flags byte returned by the device.
    public init(flagsByte: UInt8) {
        hiRes  = (flagsByte & 0x10) != 0
        invert = (flagsByte & 0x08) != 0
        target = (flagsByte & 0x04) != 0
    }

    /// The packed flags byte to send to the device.
    public var flagsByte: UInt8 {
        var byte: UInt8 = 0
        if hiRes  { byte |= 0x10 }
        if invert { byte |= 0x08 }
        if target { byte |= 0x04 }
        return byte
    }
}

/// Static capabilities reported by the device (read-only).
public struct HiResWheelCapabilities: Equatable {
    /// Whether the hardware supports high-resolution mode.
    public var supportsHiRes: Bool
    /// Whether the hardware supports scroll direction inversion.
    public var supportsInvert: Bool
    /// Whether HID++ notification routing is available.
    public var supportsTarget: Bool
    /// Multiplier applied to scroll deltas in hi-res mode.
    public var multiplier: Int

    public init(supportsHiRes: Bool, supportsInvert: Bool, supportsTarget: Bool, multiplier: Int) {
        self.supportsHiRes  = supportsHiRes
        self.supportsInvert = supportsInvert
        self.supportsTarget = supportsTarget
        self.multiplier     = multiplier
    }
}

// MARK: - Feature Module

public enum HiResWheel {

    /// Returns the current wheel mode.
    /// Function 0x00 — GetWheelMode.
    public static func getMode(device: HIDPPDevice) throws -> HiResWheelMode {
        let idx = try FeatureRegistry.index(for: .hiResWheel, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        // Response: [flags, ...]
        guard response.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        return HiResWheelMode(flagsByte: response.parameters[0])
    }

    /// Writes a new wheel mode to the device.
    /// Function 0x01 — SetWheelMode.
    public static func setMode(device: HIDPPDevice, mode: HiResWheelMode) throws {
        let idx = try FeatureRegistry.index(for: .hiResWheel, on: device)
        let params = Data([mode.flagsByte])
        _ = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)
    }

    /// Returns the static capabilities of the wheel hardware.
    /// Function 0x02 — GetWheelCapabilities.
    public static func getCapabilities(device: HIDPPDevice) throws -> HiResWheelCapabilities {
        let idx = try FeatureRegistry.index(for: .hiResWheel, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x02)
        // Response: [multiplier, flags, ...]  (flags same bit layout as mode)
        guard response.parameters.count >= 2 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let multiplier  = Int(response.parameters[0])
        let flags       = response.parameters[1]
        return HiResWheelCapabilities(
            supportsHiRes:  (flags & 0x10) != 0,
            supportsInvert: (flags & 0x08) != 0,
            supportsTarget: (flags & 0x04) != 0,
            multiplier:     multiplier
        )
    }
}
