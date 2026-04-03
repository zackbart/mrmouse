import XCTest
@testable import HIDPPCore

// MARK: - HIDTransportProtocol conformance tests using a mock

final class MockTransportDelegate: HIDTransportDelegate {
    var connectedDevices: [HIDDeviceInfo] = []
    var disconnectedDevices: [HIDDeviceInfo] = []
    var receivedReports: [(Data, HIDDeviceInfo)] = []

    func transport(_ transport: any HIDTransportProtocol, didConnectDevice device: HIDDeviceInfo) {
        connectedDevices.append(device)
    }

    func transport(_ transport: any HIDTransportProtocol, didDisconnectDevice device: HIDDeviceInfo) {
        disconnectedDevices.append(device)
    }

    func transport(_ transport: any HIDTransportProtocol, didReceiveReport data: Data, fromDevice device: HIDDeviceInfo) {
        receivedReports.append((data, device))
    }
}

// MARK: - HIDDeviceInfo tests

final class HIDDeviceInfoTests: XCTestCase {

    func testTransportTypeRawValues() {
        XCTAssertEqual(HIDDeviceInfo.TransportType.bluetooth.rawValue, "Bluetooth")
        XCTAssertEqual(HIDDeviceInfo.TransportType.usb.rawValue,       "USB")
        XCTAssertEqual(HIDDeviceInfo.TransportType.bolt.rawValue,      "Bolt")
        XCTAssertEqual(HIDDeviceInfo.TransportType.unifying.rawValue,  "Unifying")
    }

    func testDeviceInfoInit() {
        let info = HIDDeviceInfo(
            vendorID: 0x046D,
            productID: 0xB023,
            name: "MX Master 3S",
            serialNumber: "1234ABCD",
            transport: .bluetooth
        )
        XCTAssertEqual(info.vendorID,      0x046D)
        XCTAssertEqual(info.productID,     0xB023)
        XCTAssertEqual(info.name,          "MX Master 3S")
        XCTAssertEqual(info.serialNumber,  "1234ABCD")
        XCTAssertEqual(info.transport,     .bluetooth)
    }

    func testDeviceInfoWithNilSerial() {
        let info = HIDDeviceInfo(
            vendorID: 0x046D,
            productID: 0xC52B,
            name: "Unifying Receiver",
            serialNumber: nil,
            transport: .unifying
        )
        XCTAssertNil(info.serialNumber)
        XCTAssertEqual(info.transport, .unifying)
    }
}

// MARK: - HIDTransport lifecycle tests

final class HIDTransportLifecycleTests: XCTestCase {

    func testStartAndStopDoNotCrash() {
        let transport = HIDTransport()
        transport.start()
        // Give the HID thread a moment to spin up.
        Thread.sleep(forTimeInterval: 0.05)
        transport.stop()
    }

    func testDoubleStartIsIdempotent() {
        let transport = HIDTransport()
        transport.start()
        transport.start()   // second call must be a no-op
        Thread.sleep(forTimeInterval: 0.05)
        transport.stop()
    }

    func testStopWithoutStartDoesNotCrash() {
        let transport = HIDTransport()
        transport.stop()  // no-op; must not crash
    }

    func testConnectedDevicesEmptyInitially() {
        let transport = HIDTransport()
        XCTAssertTrue(transport.connectedDevices.isEmpty)
    }

    func testDelegateCanBeSetAndCleared() {
        let transport = HIDTransport()
        let delegate = MockTransportDelegate()
        transport.delegate = delegate
        XCTAssertNotNil(transport.delegate)
        transport.delegate = nil
        XCTAssertNil(transport.delegate)
    }

    func testSendReportToUnknownDeviceThrows() {
        let transport = HIDTransport()
        let unknownDevice = HIDDeviceInfo(
            vendorID: 0x046D,
            productID: 0xB023,
            name: "Ghost",
            serialNumber: nil,
            transport: .bluetooth
        )
        let report = Data([0x11, 0xFF, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try transport.sendReport(report, to: unknownDevice)) { error in
            guard case HIDPPDeviceError.deviceNotFound = error else {
                XCTFail("Expected deviceNotFound, got \(error)")
                return
            }
        }
    }

    func testSendEmptyReportThrows() {
        let transport = HIDTransport()
        let device = HIDDeviceInfo(
            vendorID: 0x046D,
            productID: 0xB023,
            name: "MX Master 3S",
            serialNumber: nil,
            transport: .bluetooth
        )
        XCTAssertThrowsError(try transport.sendReport(Data(), to: device)) { error in
            guard case HIDPPDeviceError.transportError = error else {
                XCTFail("Expected transportError, got \(error)")
                return
            }
        }
    }
}

// MARK: - HIDPPMessage round-trip tests (used by HIDTransport layer)

final class HIDPPMessageRoundTripTests: XCTestCase {

    func testShortMessageBytes() {
        let msg = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x0,
            softwareID: 0x1,
            parameters: Data([0x00, 0x00, 0x00])
        )
        let bytes = msg.bytes
        XCTAssertEqual(bytes.count, HIDPPMessage.shortLength)
        XCTAssertEqual(bytes[0], 0x10)
        XCTAssertEqual(bytes[1], 0xFF)
    }

    func testLongMessageBytes() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x01,
            featureIndex: 0x05,
            functionID: 0x1,
            softwareID: 0x1,
            parameters: Data(repeating: 0xAA, count: 16)
        )
        let bytes = msg.bytes
        XCTAssertEqual(bytes.count, HIDPPMessage.longLength)
        XCTAssertEqual(bytes[0], 0x11)
    }

    func testParseRoundTrip() {
        let original = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x02,
            featureIndex: 0x04,
            functionID: 0x3,
            softwareID: 0x2,
            parameters: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let parsed = HIDPPMessage.parse(original.bytes)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.reportID,      original.reportID)
        XCTAssertEqual(parsed?.deviceIndex,   original.deviceIndex)
        XCTAssertEqual(parsed?.featureIndex,  original.featureIndex)
        XCTAssertEqual(parsed?.functionID,    original.functionID)
        XCTAssertEqual(parsed?.softwareID,    original.softwareID)
    }

    func testParseTooShortReturnsNil() {
        XCTAssertNil(HIDPPMessage.parse(Data([0x10, 0x01])))
    }

    func testParseUnknownReportIDReturnsNil() {
        let badID = Data([0xFF, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00])
        XCTAssertNil(HIDPPMessage.parse(badID))
    }

    func testAsLongReportPadding() {
        let short = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x0,
            softwareID: 0x1,
            parameters: Data([0x01, 0x02, 0x03])
        )
        let long = short.asLongReport
        XCTAssertEqual(long.reportID, .long)
        XCTAssertEqual(long.bytes.count, HIDPPMessage.longLength)
    }

    func testIsErrorFlag() {
        let errorMsg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0xFF,
            functionID: 0x0,
            softwareID: 0x0,
            parameters: Data([0x00, 0x00, 0x02])   // invalidArgument
        )
        XCTAssertTrue(errorMsg.isError)
        XCTAssertEqual(errorMsg.errorCode, .invalidArgument)
    }
}
