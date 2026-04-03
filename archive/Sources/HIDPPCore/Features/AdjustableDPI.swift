import Foundation

// MARK: - AdjustableDPI (Feature ID: 0x2201)
//
// Wraps the HID++ 2.0 AdjustableDPI feature. DPI values are transmitted as
// big-endian UInt16 pairs in the parameter bytes.

public enum AdjustableDPI {

    // MARK: - Public API

    /// Returns the number of DPI-capable sensors on the device.
    /// Function 0x00 — GetSensorCount.
    public static func getSensorCount(device: HIDPPDevice) throws -> Int {
        let idx = try FeatureRegistry.index(for: .adjustableDPI, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        guard response.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        return Int(response.parameters[0])
    }

    /// Returns the current and default DPI for a sensor.
    /// Function 0x01 — GetSensorDPI.
    ///
    /// - Parameters:
    ///   - sensor: Zero-based sensor index (use 0 for single-sensor devices).
    /// - Returns: A tuple of (dpi: current DPI, defaultDPI: factory default DPI).
    public static func getDPI(device: HIDPPDevice, sensor: Int) throws -> (dpi: Int, defaultDPI: Int) {
        let idx = try FeatureRegistry.index(for: .adjustableDPI, on: device)
        let params = Data([UInt8(sensor)])
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)
        // Response: [sensor, dpi_hi, dpi_lo, default_dpi_hi, default_dpi_lo, ...]
        guard response.parameters.count >= 5 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let dpi = Int(response.parameters[1]) << 8 | Int(response.parameters[2])
        let defaultDPI = Int(response.parameters[3]) << 8 | Int(response.parameters[4])
        return (dpi: dpi, defaultDPI: defaultDPI)
    }

    /// Sets the DPI for a sensor.
    /// Function 0x02 — SetSensorDPI.
    ///
    /// - Parameters:
    ///   - sensor: Zero-based sensor index.
    ///   - dpi: Desired DPI value (e.g. 200–8000 for MX Master 3S).
    public static func setDPI(device: HIDPPDevice, sensor: Int, dpi: Int) throws {
        let idx = try FeatureRegistry.index(for: .adjustableDPI, on: device)
        let dpiHi = UInt8((dpi >> 8) & 0xFF)
        let dpiLo = UInt8(dpi & 0xFF)
        let params = Data([UInt8(sensor), dpiHi, dpiLo])
        _ = try device.featureRequest(featureIndex: idx, functionID: 0x02, parameters: params)
    }

    /// Returns the DPI range supported by a sensor.
    /// Function 0x03 — GetSensorDPIRange.
    ///
    /// - Returns: A tuple of (min: minimum DPI, max: maximum DPI, step: DPI step size).
    public static func getDPIRange(device: HIDPPDevice, sensor: Int) throws -> (min: Int, max: Int, step: Int) {
        let idx = try FeatureRegistry.index(for: .adjustableDPI, on: device)
        let params = Data([UInt8(sensor)])
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x03, parameters: params)
        // Response: [sensor, min_hi, min_lo, max_hi, max_lo, step_hi, step_lo, ...]
        guard response.parameters.count >= 7 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let minDPI  = Int(response.parameters[1]) << 8 | Int(response.parameters[2])
        let maxDPI  = Int(response.parameters[3]) << 8 | Int(response.parameters[4])
        let stepDPI = Int(response.parameters[5]) << 8 | Int(response.parameters[6])
        return (min: minDPI, max: maxDPI, step: stepDPI)
    }
}
