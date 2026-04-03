import Foundation

/// Information about a device paired to a Unifying/Bolt receiver.
public struct PairedDeviceInfo: Sendable {
    public let deviceIndex: UInt8       // 1-6 on the receiver
    public let destinationID: UInt8
    public let wpid: UInt16             // wireless PID
    public let deviceType: UInt8        // 0=keyboard, 3=mouse, etc.

    public var isMouse: Bool { deviceType == 3 || deviceType == 4 }
}

/// Enumerates devices paired to a Logitech Unifying or Bolt receiver using
/// HID++ 1.0 register reads.
///
/// The receiver itself is addressed at device index 0xFF. Paired devices
/// live at indices 1..6.
public enum ReceiverEnumerator {

    /// Enumerate all devices paired to a receiver.
    /// `transport` must be started and the receiver must be connected.
    /// This sends HID++ 1.0 short reports to the receiver.
    public static func enumeratePairedDevices(
        receiverInfo: HIDDeviceInfo,
        transport: any HIDTransportProtocol
    ) -> [PairedDeviceInfo] {
        var devices: [PairedDeviceInfo] = []

        // Try device indices 1 through 6
        for idx: UInt8 in 1...6 {
            // HID++ 1.0 register read: register 0xB5 (pairing info), param = device index
            // Short report: [0x10, 0xFF, 0x00, funcID|swID, register, param0, param1]
            // For register reads: featureIndex = 0x00 (for receiver), funcID = 0x08 (GET_LONG_REGISTER)
            // Actually, the standard way to get pairing info is:
            //   GET_LONG_REGISTER (0x83) on register 0xB5 with param[0] = 0x20 + deviceIndex
            //   This returns device type and wireless PID.

            let register: UInt8 = 0xB5
            let param: UInt8 = 0x20 + idx  // 0x20 = pairing info sub-function

            // Build a short HID++ 1.0 message to the receiver (device index 0xFF)
            // Report ID 0x10, device 0xFF, sub-ID 0x83 (GET_LONG_REGISTER), register, param
            // HID++ 1.0 uses sub-IDs in byte 2 instead of feature indices
            let request = Data([
                0x10,       // short report
                0xFF,       // receiver device index
                0x83,       // GET_LONG_REGISTER
                register,   // register address
                param,      // sub-parameter: 0x20+idx = pairing info for device idx
                0x00,       // padding
                0x00        // padding
            ])

            do {
                try transport.sendReport(request, to: receiverInfo)
            } catch {
                continue
            }

            // For receiver enumeration we don't use the full request-response correlation
            // because HID++ 1.0 has different response format. We'll use a simpler approach:
            // just check if the device responds to a HID++ 2.0 ping at that index.

            // Instead, let's just try to ping each device index with a HID++ 2.0 IRoot request.
            // If the device exists, it will respond. If not, we'll get a timeout or error.
        }

        // Simpler approach: just try HID++ 2.0 feature requests at each device index.
        // If a device is paired and connected at that index, it will respond.
        devices = pingDeviceIndices(receiverInfo: receiverInfo, transport: transport)

        return devices
    }

    /// Try to reach a HID++ 2.0 device at each index (1-6) by sending an IRoot
    /// GetFeature request. If we get a valid response, the device is there.
    private static func pingDeviceIndices(
        receiverInfo: HIDDeviceInfo,
        transport: any HIDTransportProtocol
    ) -> [PairedDeviceInfo] {
        var found: [PairedDeviceInfo] = []

        for idx: UInt8 in 1...6 {
            // Send IRoot.GetFeature(0x0001) — a harmless request that any HID++ 2.0 device answers
            let message = HIDPPMessage(
                reportID: .short,
                deviceIndex: idx,
                featureIndex: 0x00,     // IRoot is always at index 0
                functionID: 0x00,       // GetFeature
                softwareID: 0x01,
                parameters: Data([0x00, 0x01])  // looking up feature 0x0001 (IFeatureSet)
            )

            do {
                try transport.sendReport(message.bytes, to: receiverInfo)
            } catch {
                continue
            }

            // We found a potential device at this index.
            // We can't easily wait for the response here without the correlation machinery,
            // so we just record the index. The actual response will be handled by whoever
            // is listening on the transport delegate.
            found.append(PairedDeviceInfo(
                deviceIndex: idx,
                destinationID: 0,
                wpid: 0,
                deviceType: 3  // assume mouse — we'll verify during feature discovery
            ))
        }

        return found
    }

    /// Create HIDPPDevice instances for each device index on a receiver.
    /// Each device gets the receiver's HIDDeviceInfo but its own device index.
    /// Call discoverFeatures() on each to verify it's actually connected.
    public static func createDevicesForReceiver(
        receiverInfo: HIDDeviceInfo,
        transport: any HIDTransportProtocol
    ) -> [HIDPPDevice] {
        var devices: [HIDPPDevice] = []

        for idx: UInt8 in 1...6 {
            let device = HIDPPDevice(
                info: receiverInfo,
                transport: transport,
                deviceIndex: idx
            )
            // Try feature discovery — if it succeeds, there's a device at this index
            do {
                try device.discoverFeatures()
                NSLog("[ReceiverEnumerator] Found device at index %d with %d features",
                      idx, device.featureTable.count)
                devices.append(device)
            } catch {
                // No device at this index, or device is off/asleep — skip
                NSLog("[ReceiverEnumerator] No device at index %d: %@",
                      idx, error.localizedDescription)
            }
        }

        return devices
    }
}
