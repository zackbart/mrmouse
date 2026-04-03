import Foundation

public enum HIDPPError: UInt8, Error, CustomStringConvertible {
    case noError          = 0x00
    case unknown          = 0x01
    case invalidArgument  = 0x02
    case outOfRange       = 0x03
    case hwError          = 0x04
    case logitechInternal = 0x05
    case invalidFeatureIndex = 0x06
    case invalidFunctionID   = 0x07
    case busy             = 0x08
    case unsupported      = 0x09

    public var description: String {
        switch self {
        case .noError:          return "No error"
        case .unknown:          return "Unknown error"
        case .invalidArgument:  return "Invalid argument"
        case .outOfRange:       return "Out of range"
        case .hwError:          return "Hardware error"
        case .logitechInternal: return "Logitech internal error"
        case .invalidFeatureIndex: return "Invalid feature index"
        case .invalidFunctionID:   return "Invalid function ID"
        case .busy:             return "Device busy"
        case .unsupported:      return "Unsupported"
        }
    }
}

public enum HIDPPDeviceError: Error, CustomStringConvertible {
    case deviceNotFound
    case connectionLost
    case transportError(String)
    case featureNotSupported(UInt16)
    case timeout
    case unexpectedResponse

    public var isTimeout: Bool {
        if case .timeout = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .deviceNotFound:               return "Device not found"
        case .connectionLost:               return "Connection lost"
        case .transportError(let msg):      return "Transport error: \(msg)"
        case .featureNotSupported(let id):  return String(format: "Feature 0x%04X not supported", id)
        case .timeout:                      return "Request timed out"
        case .unexpectedResponse:           return "Unexpected response"
        }
    }
}
