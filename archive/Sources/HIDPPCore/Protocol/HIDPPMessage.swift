import Foundation

public enum HIDPPReportID: UInt8 {
    case short = 0x10  // 7 bytes total
    case long  = 0x11  // 20 bytes total
}

public struct HIDPPMessage {
    public static let shortLength = 7
    public static let longLength = 20

    public let reportID: HIDPPReportID
    public let deviceIndex: UInt8
    public let featureIndex: UInt8
    public let functionID: UInt8    // high 4 bits of byte 3
    public let softwareID: UInt8    // low 4 bits of byte 3
    public let parameters: Data

    public init(
        reportID: HIDPPReportID = .long,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionID: UInt8,
        softwareID: UInt8 = 0x01,
        parameters: Data = Data()
    ) {
        self.reportID = reportID
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.functionID = functionID
        self.softwareID = softwareID
        self.parameters = parameters
    }

    public var bytes: Data {
        let totalLength = reportID == .short ? Self.shortLength : Self.longLength
        let paramCapacity = totalLength - 4
        var data = Data(count: totalLength)
        data[0] = reportID.rawValue
        data[1] = deviceIndex
        data[2] = featureIndex
        data[3] = (functionID << 4) | (softwareID & 0x0F)
        let copyCount = min(parameters.count, paramCapacity)
        if copyCount > 0 {
            data.replaceSubrange(4..<(4 + copyCount), with: parameters.prefix(copyCount))
        }
        return data
    }

    public static func parse(_ data: Data) -> HIDPPMessage? {
        guard data.count >= shortLength else { return nil }
        guard let reportID = HIDPPReportID(rawValue: data[0]) else { return nil }

        let expectedLength = reportID == .short ? shortLength : longLength
        guard data.count >= expectedLength else { return nil }

        return HIDPPMessage(
            reportID: reportID,
            deviceIndex: data[1],
            featureIndex: data[2],
            functionID: (data[3] >> 4) & 0x0F,
            softwareID: data[3] & 0x0F,
            parameters: data.subdata(in: 4..<expectedLength)
        )
    }

    public var isError: Bool {
        featureIndex == 0xFF && reportID == .long
    }

    public var errorCode: HIDPPError? {
        guard isError, parameters.count >= 3 else { return nil }
        return HIDPPError(rawValue: parameters[2])
    }

    // Convenience: create a long report forced (for Bluetooth)
    public var asLongReport: HIDPPMessage {
        guard reportID == .short else { return self }
        var paddedParams = parameters
        let needed = Self.longLength - 4
        if paddedParams.count < needed {
            paddedParams.append(Data(count: needed - paddedParams.count))
        }
        return HIDPPMessage(
            reportID: .long,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: functionID,
            softwareID: softwareID,
            parameters: paddedParams
        )
    }
}

extension HIDPPMessage: CustomStringConvertible {
    public var description: String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "HIDPPMessage(\(hex))"
    }
}
