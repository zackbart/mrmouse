import Foundation
@testable import HIDPPCore

// MARK: - MockTransport

/// A test double for HIDTransportProtocol.
/// Records outgoing reports and returns canned responses.
final class MockTransport: HIDTransportProtocol {

    // MARK: - Protocol conformance

    weak var delegate: HIDTransportDelegate?

    private(set) var connectedDevices: [HIDDeviceInfo] = []

    // MARK: - Tracking

    /// Every (data, device) pair passed to sendReport.
    private(set) var sentReports: [(data: Data, device: HIDDeviceInfo)] = []

    /// Number of times start() was called.
    private(set) var startCallCount = 0

    /// Number of times stop() was called.
    private(set) var stopCallCount = 0

    // MARK: - Configuration

    /// If non-nil, sendReport throws this error instead of delivering a response.
    var sendError: Error?

    /// Queue of responses to deliver when sendReport is called.
    /// Each entry is a closure so callers can inspect the sent data before forming a reply.
    var responseQueue: [(Data) -> Data?] = []

    // MARK: - Protocol methods

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func sendReport(_ data: Data, to device: HIDDeviceInfo) throws {
        if let error = sendError {
            throw error
        }
        sentReports.append((data: data, device: device))

        // Deliver the next canned response if one is queued
        if !responseQueue.isEmpty {
            let provider = responseQueue.removeFirst()
            if let responseData = provider(data) {
                delegate?.transport(self, didReceiveReport: responseData, fromDevice: device)
            }
        }
    }

    // MARK: - Simulation helpers

    /// Simulate a device connecting.
    func simulateConnect(_ device: HIDDeviceInfo) {
        connectedDevices.append(device)
        delegate?.transport(self, didConnectDevice: device)
    }

    /// Simulate a device disconnecting.
    func simulateDisconnect(_ device: HIDDeviceInfo) {
        connectedDevices.removeAll { $0.productID == device.productID && $0.vendorID == device.vendorID }
        delegate?.transport(self, didDisconnectDevice: device)
    }

    /// Simulate an unsolicited incoming report (notification, button press, etc.)
    func simulateReport(_ data: Data, from device: HIDDeviceInfo) {
        delegate?.transport(self, didReceiveReport: data, fromDevice: device)
    }

    // MARK: - Convenience: enqueue a fixed response

    /// Queue a single fixed-bytes response for the next sendReport call.
    func enqueueResponse(_ data: Data) {
        responseQueue.append { _ in data }
    }

    /// Queue a response that mirrors the request with a modified featureIndex/functionID,
    /// useful for simulating echo-style protocol replies.
    func enqueueEchoResponse(deviceIndex: UInt8, featureIndex: UInt8, functionID: UInt8,
                              softwareID: UInt8 = 0x01, parameters: Data = Data()) {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: functionID,
            softwareID: softwareID,
            parameters: parameters
        )
        enqueueResponse(msg.bytes)
    }

    /// Queue an HID++ error response.
    func enqueueErrorResponse(deviceIndex: UInt8, targetFeatureIndex: UInt8,
                               targetFunctionID: UInt8, errorCode: HIDPPError) {
        // Error layout: featureIndex=0xFF, params=[targetFeature, targetFuncID, errorCode]
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: deviceIndex,
            featureIndex: 0xFF,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data([targetFeatureIndex, targetFunctionID, errorCode.rawValue])
        )
        enqueueResponse(msg.bytes)
    }
}
