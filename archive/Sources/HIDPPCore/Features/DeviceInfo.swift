import Foundation

// MARK: - DeviceInfo
//
// Reads device identification data using two features:
//   • DeviceName      (0x0005) — GetNameLength (fn 0x00) + GetName (fn 0x01)
//   • DeviceFWVersion (0x0003) — GetEntityCount (fn 0x00) + GetFWInfo (fn 0x01)

// MARK: - Data Models

/// Identifies the type of firmware entity returned by GetFWInfo.
public enum FirmwareEntityType: UInt8 {
    case mainFirmware       = 0x00
    case bootloader         = 0x01
    case hardwareRevision   = 0x02
    case other              = 0xFF

    public init(raw: UInt8) {
        self = FirmwareEntityType(rawValue: raw) ?? .other
    }
}

/// Version information for one firmware entity on the device.
public struct FirmwareInfo: Equatable {
    /// Entity type (main firmware, bootloader, etc.).
    public var type: FirmwareEntityType
    /// Version prefix string (up to 3 ASCII chars, e.g. "RQM").
    public var prefix: String
    /// Major.minor version numbers.
    public var version: (major: UInt8, minor: UInt8)
    /// Firmware build number.
    public var build: UInt16

    public init(type: FirmwareEntityType, prefix: String, version: (major: UInt8, minor: UInt8), build: UInt16) {
        self.type    = type
        self.prefix  = prefix
        self.version = version
        self.build   = build
    }

    // Synthesise Equatable since tuples don't conform automatically.
    public static func == (lhs: FirmwareInfo, rhs: FirmwareInfo) -> Bool {
        lhs.type           == rhs.type    &&
        lhs.prefix         == rhs.prefix  &&
        lhs.version.major  == rhs.version.major &&
        lhs.version.minor  == rhs.version.minor &&
        lhs.build          == rhs.build
    }
}

// MARK: - Feature Module

public enum DeviceInfo {

    // MARK: Device Name (0x0005)

    /// Reads the full UTF-8 device name from the DeviceName feature.
    ///
    /// The name may be longer than the 16-byte parameter window of a single
    /// long report, so this function calls GetName in a loop, advancing the
    /// byte offset until the entire name is assembled.
    ///
    /// Protocol:
    ///   fn 0x00 GetNameLength → params[0] = total byte length
    ///   fn 0x01 GetName(offset) → params[0..] = up to 15 UTF-8 bytes of name
    public static func getDeviceName(device: HIDPPDevice) throws -> String {
        let idx = try FeatureRegistry.index(for: .deviceName, on: device)

        // 1. Get total name length
        let lengthResponse = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        guard lengthResponse.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let totalLength = Int(lengthResponse.parameters[0])
        guard totalLength > 0 else { return "" }

        // 2. Fetch name in chunks (up to 15 bytes per call — long report has 16 params
        //    but byte 0 is the echo offset, leaving 15 for payload).
        var nameBytes = Data()
        let chunkSize = 15
        var offset = 0

        while nameBytes.count < totalLength {
            let params = Data([UInt8(offset)])
            let response = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)
            // Response: [offset_echo, char0, char1, …]
            guard response.parameters.count >= 2 else {
                throw HIDPPDeviceError.unexpectedResponse
            }
            // Skip the echoed offset byte; collect remaining as name bytes.
            let chunk = response.parameters.dropFirst(1)
            let remaining = totalLength - nameBytes.count
            nameBytes.append(contentsOf: chunk.prefix(remaining))
            offset += chunkSize
        }

        return String(bytes: nameBytes, encoding: .utf8) ?? String(bytes: nameBytes, encoding: .isoLatin1) ?? ""
    }

    // MARK: Firmware Version (0x0003)

    /// Reads firmware version information for the primary firmware entity.
    ///
    /// The device may expose multiple entities (firmware, bootloader, HW rev).
    /// This function reads entity 0 (main firmware) by default, which is
    /// the most useful for display and compatibility checks.
    ///
    /// Protocol:
    ///   fn 0x00 GetEntityCount → params[0] = count
    ///   fn 0x01 GetFWInfo(entityIndex) → type, prefix, version, build
    ///
    /// - Parameter entityIndex: Which firmware entity to read (0 = main firmware).
    public static func getFirmwareVersion(device: HIDPPDevice, entityIndex: Int = 0) throws -> FirmwareInfo {
        let idx = try FeatureRegistry.index(for: .deviceFWVersion, on: device)

        // 1. Verify the entity index is within range.
        let countResponse = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        guard countResponse.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let entityCount = Int(countResponse.parameters[0])
        guard entityIndex < entityCount else {
            throw HIDPPDeviceError.unexpectedResponse
        }

        // 2. Fetch info for the requested entity.
        let params = Data([UInt8(entityIndex)])
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x01, parameters: params)

        // Response layout:
        //   [0]:   entity type
        //   [1-3]: prefix (3 ASCII chars, zero-padded)
        //   [4]:   major version
        //   [5]:   minor version
        //   [6-7]: build number (big-endian)
        guard response.parameters.count >= 8 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let p           = response.parameters
        let entityType  = FirmwareEntityType(raw: p[0])
        let prefixBytes = p[1...3].filter { $0 != 0 }
        let prefix      = String(bytes: prefixBytes, encoding: .ascii) ?? ""
        let major       = p[4]
        let minor       = p[5]
        let build       = UInt16(p[6]) << 8 | UInt16(p[7])

        return FirmwareInfo(
            type:    entityType,
            prefix:  prefix,
            version: (major: major, minor: minor),
            build:   build
        )
    }

    /// Returns the total number of firmware entities exposed by the device.
    public static func getFirmwareEntityCount(device: HIDPPDevice) throws -> Int {
        let idx = try FeatureRegistry.index(for: .deviceFWVersion, on: device)
        let response = try device.featureRequest(featureIndex: idx, functionID: 0x00)
        guard response.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        return Int(response.parameters[0])
    }
}
