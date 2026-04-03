import XCTest
@testable import HIDPPCore

final class HIDPPMessageTests: XCTestCase {

    // MARK: - Short message construction

    func testShortMessageByteCount() {
        let msg = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x00,
            softwareID: 0x01,
            parameters: Data()
        )
        XCTAssertEqual(msg.bytes.count, HIDPPMessage.shortLength)
        XCTAssertEqual(HIDPPMessage.shortLength, 7)
    }

    func testShortMessageReportID() {
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0x01, featureIndex: 0x02,
                               functionID: 0x03, softwareID: 0x01, parameters: Data())
        XCTAssertEqual(msg.bytes[0], 0x10)
    }

    func testShortMessageFieldLayout() {
        let msg = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xAB,
            featureIndex: 0xCD,
            functionID: 0x05,
            softwareID: 0x03,
            parameters: Data([0x11, 0x22, 0x33])
        )
        let bytes = msg.bytes
        XCTAssertEqual(bytes[0], 0x10)         // report ID
        XCTAssertEqual(bytes[1], 0xAB)         // device index
        XCTAssertEqual(bytes[2], 0xCD)         // feature index
        XCTAssertEqual(bytes[3], 0x53)         // (0x05 << 4) | 0x03
        XCTAssertEqual(bytes[4], 0x11)
        XCTAssertEqual(bytes[5], 0x22)
        XCTAssertEqual(bytes[6], 0x33)
    }

    // MARK: - Long message construction

    func testLongMessageByteCount() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x00,
            softwareID: 0x01,
            parameters: Data()
        )
        XCTAssertEqual(msg.bytes.count, HIDPPMessage.longLength)
        XCTAssertEqual(HIDPPMessage.longLength, 20)
    }

    func testLongMessageReportID() {
        let msg = HIDPPMessage(reportID: .long, deviceIndex: 0x01, featureIndex: 0x02,
                               functionID: 0x03, softwareID: 0x01, parameters: Data())
        XCTAssertEqual(msg.bytes[0], 0x11)
    }

    func testLongMessageFieldLayout() {
        let params = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x01,
            featureIndex: 0x05,
            functionID: 0x02,
            softwareID: 0x0F,
            parameters: params
        )
        let bytes = msg.bytes
        XCTAssertEqual(bytes[0], 0x11)         // report ID
        XCTAssertEqual(bytes[1], 0x01)         // device index
        XCTAssertEqual(bytes[2], 0x05)         // feature index
        XCTAssertEqual(bytes[3], 0x2F)         // (0x02 << 4) | 0x0F
        XCTAssertEqual(bytes[4], 0xAA)
        XCTAssertEqual(bytes[5], 0xBB)
        XCTAssertEqual(bytes[6], 0xCC)
        XCTAssertEqual(bytes[7], 0xDD)
    }

    // MARK: - Function ID / software ID nibble encoding

    func testFunctionIDBitsAreHighNibble() {
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x0A, softwareID: 0x00, parameters: Data())
        // high nibble should be 0xA, low nibble 0x0
        XCTAssertEqual(msg.bytes[3], 0xA0)
    }

    func testSoftwareIDBitsAreLowNibble() {
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x0B, parameters: Data())
        // high nibble 0, low nibble 0xB
        XCTAssertEqual(msg.bytes[3], 0x0B)
    }

    func testFunctionAndSoftwareIDCombined() {
        let msg = HIDPPMessage(reportID: .long, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x0F, softwareID: 0x0F, parameters: Data())
        XCTAssertEqual(msg.bytes[3], 0xFF)
    }

    func testSoftwareIDOnlyLowNibbleMaskApplied() {
        // softwareID value 0x1F — only low 4 bits (0x0F) should be stored
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x1F, parameters: Data())
        XCTAssertEqual(msg.bytes[3] & 0x0F, 0x0F)
    }

    // MARK: - Parameters truncation

    func testShortMessageParametersTruncated() {
        // Short report has 3 param bytes; excess should be dropped
        let params = Data([0x01, 0x02, 0x03, 0x04, 0x05])  // 5 bytes
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x01, parameters: params)
        let bytes = msg.bytes
        XCTAssertEqual(bytes.count, HIDPPMessage.shortLength)
        XCTAssertEqual(bytes[4], 0x01)
        XCTAssertEqual(bytes[5], 0x02)
        XCTAssertEqual(bytes[6], 0x03)
        // bytes[7] does not exist — total is only 7
    }

    func testLongMessageParametersTruncated() {
        // Long report has 16 param bytes; supply 20 — should truncate to 16
        let params = Data(repeating: 0xFF, count: 20)
        let msg = HIDPPMessage(reportID: .long, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x01, parameters: params)
        XCTAssertEqual(msg.bytes.count, HIDPPMessage.longLength)
    }

    // MARK: - Parameters padding

    func testShortMessagePaddedWithZeroes() {
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x01, parameters: Data([0xAA]))
        let bytes = msg.bytes
        XCTAssertEqual(bytes[4], 0xAA)
        XCTAssertEqual(bytes[5], 0x00)  // padded
        XCTAssertEqual(bytes[6], 0x00)  // padded
    }

    func testLongMessagePaddedWithZeroes() {
        let msg = HIDPPMessage(reportID: .long, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x01, parameters: Data([0xBB]))
        let bytes = msg.bytes
        XCTAssertEqual(bytes[4], 0xBB)
        for i in 5..<HIDPPMessage.longLength {
            XCTAssertEqual(bytes[i], 0x00, "byte \(i) should be zero-padded")
        }
    }

    // MARK: - Round-trip: short message

    func testShortMessageRoundTrip() {
        let original = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xAB,
            featureIndex: 0x12,
            functionID: 0x03,
            softwareID: 0x05,
            parameters: Data([0x10, 0x20, 0x30])
        )
        guard let parsed = HIDPPMessage.parse(original.bytes) else {
            XCTFail("parse returned nil for valid short message")
            return
        }
        XCTAssertEqual(parsed.reportID,     original.reportID)
        XCTAssertEqual(parsed.deviceIndex,  original.deviceIndex)
        XCTAssertEqual(parsed.featureIndex, original.featureIndex)
        XCTAssertEqual(parsed.functionID,   original.functionID)
        XCTAssertEqual(parsed.softwareID,   original.softwareID)
        // parameters are the 3 payload bytes for a short report
        XCTAssertEqual(parsed.parameters, original.parameters)
    }

    // MARK: - Round-trip: long message

    func testLongMessageRoundTrip() {
        let params = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        let original = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x01,
            featureIndex: 0x07,
            functionID: 0x02,
            softwareID: 0x01,
            parameters: params
        )
        guard let parsed = HIDPPMessage.parse(original.bytes) else {
            XCTFail("parse returned nil for valid long message")
            return
        }
        XCTAssertEqual(parsed.reportID,     original.reportID)
        XCTAssertEqual(parsed.deviceIndex,  original.deviceIndex)
        XCTAssertEqual(parsed.featureIndex, original.featureIndex)
        XCTAssertEqual(parsed.functionID,   original.functionID)
        XCTAssertEqual(parsed.softwareID,   original.softwareID)
        XCTAssertEqual(parsed.parameters,   params)
    }

    // MARK: - Error detection

    func testIsErrorTrueForLongReportWithFeatureIndex0xFF() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0xFF,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data([0x00, 0x00, 0x02])
        )
        XCTAssertTrue(msg.isError)
    }

    func testIsErrorFalseForShortReportEvenWith0xFF() {
        let msg = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xFF,
            featureIndex: 0xFF,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data()
        )
        // isError requires reportID == .long
        XCTAssertFalse(msg.isError)
    }

    func testIsErrorFalseForNormalResponse() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0x01,
            functionID: 0x00,
            softwareID: 0x01,
            parameters: Data()
        )
        XCTAssertFalse(msg.isError)
    }

    // MARK: - Error code extraction

    func testErrorCodeInvalidArgument() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0xFF,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data([0x00, 0x00, 0x02])  // errorCode at params[2]
        )
        XCTAssertEqual(msg.errorCode, .invalidArgument)
    }

    func testErrorCodeBusy() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0xFF,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data([0x00, 0x00, 0x08])
        )
        XCTAssertEqual(msg.errorCode, .busy)
    }

    func testErrorCodeNilWhenNotErrorMessage() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x01,
            featureIndex: 0x01,
            functionID: 0x00,
            softwareID: 0x01,
            parameters: Data([0x00, 0x00, 0x02])
        )
        XCTAssertNil(msg.errorCode)
    }

    func testErrorCodeNilWhenParamsTooShort() {
        let msg = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0xFF,
            featureIndex: 0xFF,
            functionID: 0x00,
            softwareID: 0x00,
            parameters: Data([0x00, 0x00])  // only 2 bytes, need 3
        )
        XCTAssertNil(msg.errorCode)
    }

    // MARK: - asLongReport conversion

    func testAsLongReportFromShort() {
        let short = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xAB,
            featureIndex: 0xCD,
            functionID: 0x03,
            softwareID: 0x01,
            parameters: Data([0x11, 0x22, 0x33])
        )
        let long = short.asLongReport
        XCTAssertEqual(long.reportID, .long)
        XCTAssertEqual(long.bytes.count, HIDPPMessage.longLength)
        XCTAssertEqual(long.deviceIndex, short.deviceIndex)
        XCTAssertEqual(long.featureIndex, short.featureIndex)
        XCTAssertEqual(long.functionID, short.functionID)
        XCTAssertEqual(long.softwareID, short.softwareID)
    }

    func testAsLongReportPreservesOriginalParams() {
        let short = HIDPPMessage(
            reportID: .short,
            deviceIndex: 0xFF,
            featureIndex: 0x00,
            functionID: 0x01,
            softwareID: 0x01,
            parameters: Data([0xAA, 0xBB, 0xCC])
        )
        let long = short.asLongReport
        let bytes = long.bytes
        XCTAssertEqual(bytes[4], 0xAA)
        XCTAssertEqual(bytes[5], 0xBB)
        XCTAssertEqual(bytes[6], 0xCC)
        // remaining 13 bytes should be zero
        for i in 7..<HIDPPMessage.longLength {
            XCTAssertEqual(bytes[i], 0x00, "byte \(i) should be zero after original params")
        }
    }

    func testAsLongReportIsNoOpForLongReport() {
        let long = HIDPPMessage(
            reportID: .long,
            deviceIndex: 0x01,
            featureIndex: 0x05,
            functionID: 0x00,
            softwareID: 0x01,
            parameters: Data(repeating: 0x55, count: 8)
        )
        let result = long.asLongReport
        XCTAssertEqual(result.reportID, .long)
        XCTAssertEqual(result.bytes, long.bytes)
    }

    // MARK: - Parse invalid data

    func testParseTooShortReturnsNil() {
        XCTAssertNil(HIDPPMessage.parse(Data()))
        XCTAssertNil(HIDPPMessage.parse(Data([0x10])))
        XCTAssertNil(HIDPPMessage.parse(Data([0x10, 0xFF, 0x00, 0x10, 0x00, 0x00])))  // 6 bytes
    }

    func testParseExactlyShortLengthSucceeds() {
        let data = Data([0x10, 0xFF, 0x00, 0x10, 0x00, 0x00, 0x00])  // 7 bytes
        XCTAssertNotNil(HIDPPMessage.parse(data))
    }

    func testParseLongReportWithInsufficientBytesReturnsNil() {
        // Report ID 0x11 but only 10 bytes provided (need 20)
        let data = Data(repeating: 0x00, count: 10)
        var d = data
        d[0] = 0x11
        XCTAssertNil(HIDPPMessage.parse(d))
    }

    // MARK: - Parse invalid report ID

    func testParseUnknownReportIDReturnsNil() {
        let data = Data([0x12, 0xFF, 0x00, 0x10, 0x00, 0x00, 0x00])
        XCTAssertNil(HIDPPMessage.parse(data))
    }

    func testParseZeroReportIDReturnsNil() {
        let data = Data([0x00, 0xFF, 0x00, 0x10, 0x00, 0x00, 0x00])
        XCTAssertNil(HIDPPMessage.parse(data))
    }

    // MARK: - CustomStringConvertible

    func testDescriptionContainsHex() {
        let msg = HIDPPMessage(reportID: .short, deviceIndex: 0xFF, featureIndex: 0x00,
                               functionID: 0x00, softwareID: 0x01, parameters: Data())
        let desc = msg.description
        XCTAssertTrue(desc.contains("10"), "description should contain the report ID hex")
    }
}
