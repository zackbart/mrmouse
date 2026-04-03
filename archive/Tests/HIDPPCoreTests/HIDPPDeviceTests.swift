import XCTest
@testable import HIDPPCore

// MARK: - Helpers

private func makeInfo(transport: HIDDeviceInfo.TransportType = .usb) -> HIDDeviceInfo {
    HIDDeviceInfo(
        vendorID: 0x046D,
        productID: 0xB023,
        name: "MX Master 3S",
        serialNumber: "TEST001",
        transport: transport
    )
}

// MARK: - HIDPPDeviceTests

final class HIDPPDeviceTests: XCTestCase {

    // MARK: - featureRequest: correct message construction

    func testFeatureRequestSendsCorrectBytes() throws {
        let transport = MockTransport()
        let info = makeInfo()
        let device = HIDPPDevice(info: info, transport: transport, deviceIndex: 0xFF)

        // Pre-load the feature table so no IRoot lookup is needed
        device.featureTable[0x0001] = 0x05

        // Enqueue a valid response that matches featureIndex=0x05, functionID=0x00
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x05,
            functionID: 0x00,
            parameters: Data([0x03])  // e.g. feature count = 3
        )

        let response = try device.featureRequest(featureIndex: 0x05, functionID: 0x00)

        // Verify a report was sent
        XCTAssertEqual(transport.sentReports.count, 1)
        let sent = transport.sentReports[0].data

        // Report ID for USB with small params: short (0x10) or long (0x11 default)
        // The implementation uses long for Bluetooth; USB with <= 3 params uses short
        XCTAssertTrue(sent[0] == 0x10 || sent[0] == 0x11)
        XCTAssertEqual(sent[1], 0xFF)  // device index
        XCTAssertEqual(sent[2], 0x05)  // feature index
        // Verify response was received
        XCTAssertEqual(response.parameters[0], 0x03)
    }

    func testFeatureRequestUsesBluetooth() throws {
        let transport = MockTransport()
        let info = makeInfo(transport: .bluetooth)
        let device = HIDPPDevice(info: info, transport: transport, deviceIndex: 0xFF)

        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x00,
            parameters: Data([0x07])
        )

        _ = try device.featureRequest(featureIndex: 0x00, functionID: 0x00)

        let sent = transport.sentReports[0].data
        // Bluetooth always uses long report
        XCTAssertEqual(sent[0], 0x11)
        XCTAssertEqual(sent.count, HIDPPMessage.longLength)
    }

    func testFeatureRequestWithParameters() throws {
        let transport = MockTransport()
        let info = makeInfo()
        let device = HIDPPDevice(info: info, transport: transport, deviceIndex: 0x01)

        transport.enqueueEchoResponse(
            deviceIndex: 0x01,
            featureIndex: 0x03,
            functionID: 0x01,
            parameters: Data([0x00, 0x0E, 0x10, 0x00, 0x00])
        )

        let params = Data([0x00, 0x01])
        let response = try device.featureRequest(featureIndex: 0x03, functionID: 0x01, parameters: params)
        XCTAssertGreaterThanOrEqual(response.parameters.count, 1)
    }

    // MARK: - featureRequest: error response throws HIDPPError

    func testFeatureRequestThrowsOnErrorResponse() {
        let transport = MockTransport()
        let info = makeInfo()
        let device = HIDPPDevice(info: info, transport: transport, deviceIndex: 0xFF)

        transport.enqueueErrorResponse(
            deviceIndex: 0xFF,
            targetFeatureIndex: 0x00,
            targetFunctionID: 0x00,
            errorCode: .invalidArgument
        )

        XCTAssertThrowsError(
            try device.featureRequest(featureIndex: 0x00, functionID: 0x00)
        ) { error in
            guard let hidError = error as? HIDPPError else {
                XCTFail("Expected HIDPPError, got \(error)")
                return
            }
            XCTAssertEqual(hidError, .invalidArgument)
        }
    }

    func testFeatureRequestThrowsBusyError() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        transport.enqueueErrorResponse(
            deviceIndex: 0xFF,
            targetFeatureIndex: 0x05,
            targetFunctionID: 0x01,
            errorCode: .busy
        )

        XCTAssertThrowsError(
            try device.featureRequest(featureIndex: 0x05, functionID: 0x01)
        ) { error in
            XCTAssertEqual(error as? HIDPPError, .busy)
        }
    }

    // MARK: - featureRequest: timeout

    func testFeatureRequestTimesOutWithNoResponse() {
        let transport = MockTransport()
        // No response enqueued — sendReport delivers nothing
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        // Use a very short timeout by subclassing or just accept the 2s default is tested here.
        // We verify the correct error type is returned.
        // Note: this test will take ~2 seconds due to the built-in semaphore timeout.
        // In CI it's fine; swap for a custom timeout if desired.
        let start = Date()
        XCTAssertThrowsError(
            try device.featureRequest(featureIndex: 0x00, functionID: 0x00)
        ) { error in
            guard case HIDPPDeviceError.timeout = error else {
                XCTFail("Expected timeout error, got \(error)")
                return
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(elapsed, 1.5, "Should have waited roughly 2 seconds for timeout")
    }

    // MARK: - featureRequest: transport send error

    func testFeatureRequestThrowsTransportError() {
        let transport = MockTransport()
        transport.sendError = HIDPPDeviceError.transportError("mock failure")
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        XCTAssertThrowsError(
            try device.featureRequest(featureIndex: 0x00, functionID: 0x00)
        ) { error in
            guard case HIDPPDeviceError.transportError = error else {
                XCTFail("Expected transportError, got \(error)")
                return
            }
        }
    }

    // MARK: - handleReport: correlation

    func testHandleReportCorrelatesResponse() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        // Enqueue a response that is delivered synchronously via MockTransport.sendReport
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x04,
            functionID: 0x02,
            parameters: Data([0xDE, 0xAD])
        )

        // featureRequest sends → MockTransport delivers response → handleReport is NOT called yet
        // MockTransport bypasses handleReport — we need to wire up the delegate.
        // Set up device as its own delegate via handleReport
        let response = try? device.featureRequest(featureIndex: 0x04, functionID: 0x02)
        // MockTransport calls delegate?.transport(_:didReceiveReport:fromDevice:) but
        // HIDPPDevice doesn't conform to HIDTransportDelegate. The transport's delegate
        // delivers to whoever registered. We need to wire this up manually.
        // The actual correlation path is: transport delegate → device.handleReport()
        // For this to work, we need an adapter. Let's test handleReport directly instead.

        // Direct handleReport test
        let responseMsg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0x04,
            functionID: 0x02,
            softwareID: 0x01,
            parameters: Data([0xDE, 0xAD])
        )
        _ = response  // suppress unused warning

        // Dispatch a request on a background thread, then call handleReport from here
        let transport2 = MockTransport()
        transport2.sendError = nil  // no auto-response
        let device2 = HIDPPDevice(info: makeInfo(), transport: transport2, deviceIndex: 0xFF)

        var receivedResponse: HIDPPMessage?
        var requestError: Error?

        let exp = expectation(description: "featureRequest completes")
        DispatchQueue.global().async {
            do {
                receivedResponse = try device2.featureRequest(featureIndex: 0x04, functionID: 0x02)
            } catch {
                requestError = error
            }
            exp.fulfill()
        }

        // Give the background thread time to block on the semaphore
        Thread.sleep(forTimeInterval: 0.1)

        // Deliver matching response
        device2.handleReport(responseMsg.bytes)

        wait(for: [exp], timeout: 5.0)

        XCTAssertNil(requestError)
        XCTAssertNotNil(receivedResponse)
        XCTAssertEqual(receivedResponse?.parameters, Data([0xDE, 0xAD, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    // MARK: - handleReport: wrong device index is ignored

    func testHandleReportIgnoresWrongDeviceIndex() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0x01)

        var notificationReceived = false
        device.onNotification = { _ in notificationReceived = true }

        // Send a report with a different device index
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x02,  // wrong index
            featureIndex: 0x05,
            functionID: 0x00,
            softwareID: 0x01,
            parameters: Data()
        )
        device.handleReport(msg.bytes)

        XCTAssertFalse(notificationReceived)
    }

    // MARK: - handleReport: uncorrelated reports as notifications

    func testUncorrelatedReportDeliveredAsNotification() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        var notifiedMessage: HIDPPMessage?
        device.onNotification = { notifiedMessage = $0 }

        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0x09,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data([0x01, 0x02, 0x03])
        )
        device.handleReport(msg.bytes)

        XCTAssertNotNil(notifiedMessage)
        XCTAssertEqual(notifiedMessage?.featureIndex, 0x09)
        XCTAssertEqual(notifiedMessage?.parameters.prefix(3), Data([0x01, 0x02, 0x03]))
    }

    func testHandleReportWithInvalidDataIsIgnored() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        var notificationReceived = false
        device.onNotification = { _ in notificationReceived = true }

        // Too short to parse
        device.handleReport(Data([0x11, 0xFF]))
        XCTAssertFalse(notificationReceived)
    }

    // MARK: - hasFeature

    func testHasFeatureReturnsTrueWhenCached() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)
        device.featureTable[0x1004] = 0x03
        XCTAssertTrue(device.hasFeature(0x1004))
    }

    func testHasFeatureReturnsFalseWhenAbsent() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)
        XCTAssertFalse(device.hasFeature(0x2201))
    }

    // MARK: - getFeatureIndex

    func testGetFeatureIndexReturnsCachedValue() throws {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)
        device.featureTable[0x2201] = 0x07

        let idx = try device.getFeatureIndex(featureID: 0x2201)
        XCTAssertEqual(idx, 0x07)
        // Should not have sent any reports since it was cached
        XCTAssertEqual(transport.sentReports.count, 0)
    }

    func testGetFeatureIndexThrowsWhenDeviceReturnsZero() {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        // IRoot GetFeature returns index 0 → feature not supported
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x00,
            parameters: Data([0x00])  // index = 0
        )

        XCTAssertThrowsError(try device.getFeatureIndex(featureID: 0x2201)) { error in
            guard case HIDPPDeviceError.featureNotSupported(let id) = error else {
                XCTFail("Expected featureNotSupported, got \(error)")
                return
            }
            XCTAssertEqual(id, 0x2201)
        }
    }

    func testGetFeatureIndexCachesResult() throws {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        // IRoot returns index 5 for feature 0x1004
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x00,
            parameters: Data([0x05])
        )

        let idx = try device.getFeatureIndex(featureID: 0x1004)
        XCTAssertEqual(idx, 0x05)
        XCTAssertEqual(device.featureTable[0x1004], 0x05)
    }

    // MARK: - Feature discovery

    func testDiscoverFeaturesPopulatesTable() throws {
        let transport = MockTransport()
        let device = HIDPPDevice(info: makeInfo(), transport: transport, deviceIndex: 0xFF)

        // Response 1: IRoot.GetFeature(0x0001) → feature index 1
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x00,
            parameters: Data([0x01])
        )
        // Response 2: IFeatureSet.GetCount() → 2 features
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x01,
            functionID: 0x00,
            parameters: Data([0x02])
        )
        // Response 3: GetFeatureID(1) → 0x2201 (AdjustableDPI)
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x01,
            functionID: 0x01,
            parameters: Data([0x22, 0x01, 0x00])
        )
        // Response 4: GetFeatureID(2) → 0x1004 (UnifiedBattery)
        transport.enqueueEchoResponse(
            deviceIndex: 0xFF,
            featureIndex: 0x01,
            functionID: 0x01,
            parameters: Data([0x10, 0x04, 0x00])
        )

        try device.discoverFeatures()

        XCTAssertEqual(device.featureTable[0x0000], 0x00)  // IRoot always index 0
        XCTAssertEqual(device.featureTable[0x0001], 0x01)
        XCTAssertEqual(device.featureTable[0x2201], 0x01)
        XCTAssertEqual(device.featureTable[0x1004], 0x02)
    }

    // MARK: - HIDPPFeature enum

    func testFeatureEnumRawValues() {
        XCTAssertEqual(HIDPPFeature.iRoot.rawValue,           0x0000)
        XCTAssertEqual(HIDPPFeature.iFeatureSet.rawValue,     0x0001)
        XCTAssertEqual(HIDPPFeature.unifiedBattery.rawValue,  0x1004)
        XCTAssertEqual(HIDPPFeature.adjustableDPI.rawValue,   0x2201)
        XCTAssertEqual(HIDPPFeature.smartShift.rawValue,      0x2110)
        XCTAssertEqual(HIDPPFeature.reprogControlsV4.rawValue, 0x1B04)
    }

    func testFeatureNames() {
        XCTAssertEqual(HIDPPFeature.iRoot.name, "IRoot")
        XCTAssertEqual(HIDPPFeature.unifiedBattery.name, "Unified Battery")
        XCTAssertEqual(HIDPPFeature.adjustableDPI.name, "Adjustable DPI")
    }
}
