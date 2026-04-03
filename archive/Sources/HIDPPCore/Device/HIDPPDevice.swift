import Foundation

public final class HIDPPDevice: @unchecked Sendable {
    public let info: HIDDeviceInfo
    public var featureTable: [UInt16: UInt8] = [:]  // featureID -> featureIndex

    private let transport: any HIDTransportProtocol
    private let deviceIndex: UInt8

    // Request-response correlation
    private var pendingRequests: [RequestKey: PendingRequest] = [:]
    private let requestLock = NSLock()
    private let softwareID: UInt8 = 0x01

    // Notification handler for diverted buttons, battery, etc.
    public var onNotification: ((HIDPPMessage) -> Void)?

    public init(info: HIDDeviceInfo, transport: any HIDTransportProtocol, deviceIndex: UInt8 = 0xFF) {
        self.info = info
        self.transport = transport
        self.deviceIndex = deviceIndex
        // Register self as delegate so sendReport → response → handleReport works
        // automatically when used standalone (e.g. in tests or without a higher-level
        // coordinator).  AppState overrides this with its own delegate after construction.
        transport.delegate = self
    }

    // MARK: - Feature Discovery

    public func discoverFeatures() throws {
        // IRoot (0x0000) is always at feature index 0
        featureTable[0x0000] = 0x00

        // Discover IFeatureSet (0x0001)
        let featureSetIndex = try getFeatureIndex(featureID: 0x0001)
        featureTable[0x0001] = featureSetIndex

        // Get feature count
        let countResponse = try featureRequest(
            featureIndex: featureSetIndex,
            functionID: 0x00  // GetCount
        )
        guard countResponse.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }
        let featureCount = Int(countResponse.parameters[0])

        // Enumerate all features
        for i in 1...featureCount {
            let response = try featureRequest(
                featureIndex: featureSetIndex,
                functionID: 0x01,  // GetFeatureID
                parameters: Data([UInt8(i)])
            )
            guard response.parameters.count >= 2 else { continue }
            let featureID = UInt16(response.parameters[0]) << 8 | UInt16(response.parameters[1])
            if featureID != 0x0000 {
                featureTable[featureID] = UInt8(i)
            }
        }
    }

    public func getFeatureIndex(featureID: UInt16) throws -> UInt8 {
        if let cached = featureTable[featureID] {
            return cached
        }

        // Query IRoot (index 0) function 0 (GetFeature)
        let msb = UInt8((featureID >> 8) & 0xFF)
        let lsb = UInt8(featureID & 0xFF)
        let response = try featureRequest(
            featureIndex: 0x00,
            functionID: 0x00,
            parameters: Data([msb, lsb])
        )

        guard response.parameters.count >= 1 else {
            throw HIDPPDeviceError.unexpectedResponse
        }

        let index = response.parameters[0]
        if index == 0 {
            throw HIDPPDeviceError.featureNotSupported(featureID)
        }

        featureTable[featureID] = index
        return index
    }

    public func hasFeature(_ featureID: UInt16) -> Bool {
        featureTable[featureID] != nil
    }

    // MARK: - Feature Request

    public func featureRequest(
        featureIndex: UInt8,
        functionID: UInt8,
        parameters: Data = Data()
    ) throws -> HIDPPMessage {
        let useLong = info.transport == .bluetooth || parameters.count > 3
        let reportID: HIDPPReportID = useLong ? .long : .short

        let message = HIDPPMessage(
            reportID: reportID,
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: functionID,
            softwareID: softwareID,
            parameters: parameters
        )

        let key = RequestKey(featureIndex: featureIndex, functionID: functionID)
        let pending = PendingRequest()

        requestLock.lock()
        pendingRequests[key] = pending
        requestLock.unlock()

        try transport.sendReport(message.bytes, to: info)

        // Wait for response with timeout
        let result = pending.semaphore.wait(timeout: .now() + 2.0)

        requestLock.lock()
        pendingRequests.removeValue(forKey: key)
        requestLock.unlock()

        guard result == .success else {
            throw HIDPPDeviceError.timeout
        }

        guard let response = pending.response else {
            throw HIDPPDeviceError.unexpectedResponse
        }

        if let error = response.errorCode {
            throw error
        }

        return response
    }

    // MARK: - Report Handling

    public func handleReport(_ data: Data) {
        guard let message = HIDPPMessage.parse(data) else { return }

        // Check if this matches the device index
        guard message.deviceIndex == deviceIndex else { return }

        // For error responses (featureIndex == 0xFF), the parameters contain the original
        // featureIndex and functionID of the failed request — use those to look up the pending.
        let key: RequestKey
        if message.isError, message.parameters.count >= 2 {
            key = RequestKey(featureIndex: message.parameters[0],
                             functionID: message.parameters[1])
        } else {
            key = RequestKey(featureIndex: message.featureIndex, functionID: message.functionID)
        }

        requestLock.lock()
        let pending = pendingRequests[key]
        requestLock.unlock()

        if let pending {
            pending.response = message
            pending.semaphore.signal()
        } else {
            // Not a response to any pending request — treat as notification
            onNotification?(message)
        }
    }
}

// MARK: - HIDTransportDelegate (self-registration for standalone / test use)

extension HIDPPDevice: HIDTransportDelegate {

    /// Forwards incoming report bytes to `handleReport`. Only called when `HIDPPDevice` is
    /// the transport's delegate (i.e. standalone/test use without a higher-level coordinator).
    public func transport(
        _ transport: any HIDTransportProtocol,
        didReceiveReport data: Data,
        fromDevice device: HIDDeviceInfo
    ) {
        handleReport(data)
    }

    /// Connect / disconnect events are not meaningful at the device level — they are
    /// handled by the higher-level coordinator (e.g. AppState).  These are no-ops.
    public func transport(
        _ transport: any HIDTransportProtocol,
        didConnectDevice device: HIDDeviceInfo
    ) {}

    public func transport(
        _ transport: any HIDTransportProtocol,
        didDisconnectDevice device: HIDDeviceInfo
    ) {}
}

// MARK: - Internal Types

private struct RequestKey: Hashable {
    let featureIndex: UInt8
    let functionID: UInt8
}

private final class PendingRequest {
    let semaphore = DispatchSemaphore(value: 0)
    var response: HIDPPMessage?
}

// MARK: - Feature Registry

public enum HIDPPFeature: UInt16 {
    case iRoot             = 0x0000
    case iFeatureSet       = 0x0001
    case deviceFWVersion   = 0x0003
    case deviceName        = 0x0005
    case unifiedBattery    = 0x1004
    case reprogControlsV4  = 0x1B04
    case adjustableDPI     = 0x2201
    case smartShift        = 0x2110
    case hiResWheel        = 0x2121
    case thumbWheel        = 0x2150
    case gesture2          = 0x6501
    case changeHost        = 0x1814
    case hostsInfo         = 0x1815

    public var name: String {
        switch self {
        case .iRoot:             return "IRoot"
        case .iFeatureSet:       return "IFeatureSet"
        case .deviceFWVersion:   return "Device FW Version"
        case .deviceName:        return "Device Name"
        case .unifiedBattery:    return "Unified Battery"
        case .reprogControlsV4:  return "Reprog Controls V4"
        case .adjustableDPI:     return "Adjustable DPI"
        case .smartShift:        return "Smart Shift"
        case .hiResWheel:        return "HiRes Wheel"
        case .thumbWheel:        return "Thumb Wheel"
        case .gesture2:          return "Gesture 2"
        case .changeHost:        return "Change Host"
        case .hostsInfo:         return "Hosts Info"
        }
    }
}
