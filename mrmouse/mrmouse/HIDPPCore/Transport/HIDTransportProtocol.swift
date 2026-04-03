import Foundation

public struct HIDDeviceInfo: Sendable {
    public let vendorID: Int
    public let productID: Int
    public let name: String
    public let serialNumber: String?
    public let transport: TransportType

    public enum TransportType: String, Sendable {
        case bluetooth = "Bluetooth"
        case usb = "USB"
        case bolt = "Bolt"
        case unifying = "Unifying"
    }

    public init(vendorID: Int, productID: Int, name: String, serialNumber: String?, transport: TransportType) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.serialNumber = serialNumber
        self.transport = transport
    }
}

public protocol HIDTransportDelegate: AnyObject {
    func transport(_ transport: any HIDTransportProtocol, didReceiveReport data: Data, fromDevice device: HIDDeviceInfo)
    func transport(_ transport: any HIDTransportProtocol, didConnectDevice device: HIDDeviceInfo)
    func transport(_ transport: any HIDTransportProtocol, didDisconnectDevice device: HIDDeviceInfo)
}

public protocol HIDTransportProtocol: AnyObject {
    var delegate: HIDTransportDelegate? { get set }
    var connectedDevices: [HIDDeviceInfo] { get }

    func start()
    func stop()
    func sendReport(_ data: Data, to device: HIDDeviceInfo) throws
}
