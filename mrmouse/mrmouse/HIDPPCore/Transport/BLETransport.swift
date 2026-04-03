import CoreBluetooth
import Foundation

// MARK: - Logitech BLE GATT Constants

/// Logitech vendor-specific GATT service UUID.
/// Contains HID++ protocol commands/responses/notifications.
private let kLogitechServiceUUID = CBUUID(string: "00010000-0000-1000-8000-011f2000046d")

/// Known Bluetooth product IDs for Logitech mice (used for name-based matching fallback).
private let kLogitechNamePrefixes = ["MX Master", "MX Anywhere", "MX Ergo", "MX Vertical"]

// MARK: - BLETransport

/// CoreBluetooth-based transport for Logitech HID++ devices.
///
/// Communicates directly with Logitech mice over BLE GATT, bypassing the Bolt receiver
/// and macOS kernel-level HID++ blocking. Uses the Logitech vendor-specific GATT service
/// for HID++ commands, responses, and unsolicited notifications.
///
/// BLE GATT flow:
///   1. Scan for peripherals advertising the Logitech service UUID
///   2. Connect → discover service → discover characteristics
///   3. Enable notifications on the report characteristic
///   4. Write HID++ commands to the write characteristic (write-without-response)
///   5. Receive HID++ responses/notifications via GATT notify callbacks
public final class BLETransport: NSObject, HIDTransportProtocol {

    // MARK: Public interface

    public weak var delegate: HIDTransportDelegate?

    public private(set) var connectedDevices: [HIDDeviceInfo] = []

    // MARK: CoreBluetooth

    private var centralManager: CBCentralManager?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var deviceInfoMap: [UUID: HIDDeviceInfo] = [:]
    private var logitechServiceMap: [UUID: CBService] = [:]
    private var writeCharMap: [UUID: CBCharacteristic] = [:]
    private var reportCharMap: [UUID: CBCharacteristic] = [:]
    private var isScanning = false
    private let lock = NSLock()

    /// Used to match peripherals in sendReport by serialNumber (UUID string).
    private var peripheralIDBySerial: [String: UUID] = [:]

    // MARK: - Lifecycle

    public override init() {
        super.init()
    }

    deinit {
        stop()
    }

    // MARK: - HIDTransportProtocol

    public func start() {
        guard centralManager == nil else { return }
        NSLog("[BLETransport] Starting BLE transport")
        centralManager = CBCentralManager(delegate: self, queue: nil) // main queue
    }

    public func stop() {
        isScanning = false
        centralManager?.stopScan()
        if let manager = centralManager {
            for peripheral in connectedPeripherals.values {
                manager.cancelPeripheralConnection(peripheral)
            }
        }
        centralManager = nil
        connectedPeripherals.removeAll()
        deviceInfoMap.removeAll()
        logitechServiceMap.removeAll()
        writeCharMap.removeAll()
        reportCharMap.removeAll()
        peripheralIDBySerial.removeAll()
        connectedDevices = []
    }

    public func sendReport(_ data: Data, to device: HIDDeviceInfo) throws {
        let serial = device.serialNumber ?? ""
        guard let peripheralUUID = peripheralIDBySerial[serial],
              let peripheral = connectedPeripherals[peripheralUUID],
              let writeChar = writeCharMap[peripheralUUID]
        else {
            throw BLETransportError.notConnected
        }

        let hex = data.prefix(min(data.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[BLETransport] TX: %@", hex)

        peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
    }

    // MARK: - Scanning

    private func startScanning() {
        guard let manager = centralManager, manager.state == .poweredOn, !isScanning else { return }

        isScanning = true
        NSLog("[BLETransport] Scanning for peripherals (name-based matching)")
        // Don't filter by service UUID — Logitech devices may not advertise it.
        // Match by name in didDiscover callback instead.
        manager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    private func stopScanning() {
        guard isScanning else { return }
        centralManager?.stopScan()
        isScanning = false
        NSLog("[BLETransport] Stopped scanning")
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            NSLog("[BLETransport] Bluetooth powered on — starting scan")
            startScanning()
        case .poweredOff:
            NSLog("[BLETransport] Bluetooth powered off")
            isScanning = false
        case .unauthorized:
            NSLog("[BLETransport] Bluetooth unauthorized — check System Settings > Privacy")
            isScanning = false
        case .unsupported:
            NSLog("[BLETransport] Bluetooth unsupported on this device")
        default:
            NSLog("[BLETransport] Bluetooth state: %d", central.state.rawValue)
        }
    }

    public func centralManager(_ central: CBCentralManager,
                                didDiscover peripheral: CBPeripheral,
                                advertisementData: [String: Any],
                                rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown"
        NSLog("[BLETransport] Discovered: %@ (RSSI: %@)", name, RSSI)

        // Prefer name-based filtering as secondary gate — only connect to known Logitech mice
        let isLogitech = kLogitechNamePrefixes.contains { name.hasPrefix($0) }
            || (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                .map { prefix in kLogitechNamePrefixes.contains { prefix.hasPrefix($0) } } ?? false

        guard isLogitech else {
            NSLog("[BLETransport] Skipping non-Logitech device: %@", name)
            return
        }

        guard connectedPeripherals[peripheral.identifier] == nil else {
            NSLog("[BLETransport] Already connected/connected to %@", name)
            return
        }

        NSLog("[BLETransport] Connecting to %@", name)
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        NSLog("[BLETransport] Connected to %@", peripheral.name ?? "Unknown")
        peripheral.delegate = self
        peripheral.discoverServices([kLogitechServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager,
                                didFailToConnect peripheral: CBPeripheral,
                                error: Error?) {
        NSLog("[BLETransport] Failed to connect to %@: %@",
              peripheral.name ?? "Unknown", error?.localizedDescription ?? "unknown error")
    }

    public func centralManager(_ central: CBCentralManager,
                                didDisconnectPeripheral peripheral: CBPeripheral,
                                error: Error?) {
        let id = peripheral.identifier
        NSLog("[BLETransport] Disconnected from %@: %@",
              peripheral.name ?? "Unknown", error?.localizedDescription ?? "clean disconnect")

        lock.lock()
        connectedPeripherals.removeValue(forKey: id)
        let info = deviceInfoMap.removeValue(forKey: id)
        logitechServiceMap.removeValue(forKey: id)
        writeCharMap.removeValue(forKey: id)
        reportCharMap.removeValue(forKey: id)
        if let serial = info?.serialNumber { peripheralIDBySerial.removeValue(forKey: serial) }
        updateConnectedDevices()
        lock.unlock()

        if let info {
            delegate?.transport(self, didDisconnectDevice: info)
        }
    }

    private func updateConnectedDevices() {
        connectedDevices = Array(deviceInfoMap.values)
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            NSLog("[BLETransport] Service discovery error: %@", error.localizedDescription)
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == kLogitechServiceUUID {
                NSLog("[BLETransport] Found Logitech service — discovering characteristics")
                logitechServiceMap[peripheral.identifier] = service
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                            didDiscoverCharacteristicsFor service: CBService,
                            error: Error?) {
        if let error {
            NSLog("[BLETransport] Characteristic discovery error: %@", error.localizedDescription)
            return
        }

        guard let characteristics = service.characteristics else { return }

        var writeChar: CBCharacteristic?
        var reportChar: CBCharacteristic?

        for char in characteristics {
            NSLog("[BLETransport]   Characteristic %@: properties=%@",
                  char.uuid.uuidString, char.properties.debugDescription)

            if char.properties.contains(.writeWithoutResponse) {
                writeChar = char
                NSLog("[BLETransport]   → Write characteristic: %@", char.uuid.uuidString)
            }

            if char.properties.contains(.notify) {
                reportChar = char
                NSLog("[BLETransport]   → Report characteristic: %@", char.uuid.uuidString)
                peripheral.setNotifyValue(true, for: char)
            }
        }

        // Some Logitech BLE devices have a single characteristic that supports both
        // write and notify. Fall back to the first characteristic if needed.
        if writeChar == nil, let first = characteristics.first {
            writeChar = first
            NSLog("[BLETransport]   → Fallback write characteristic: %@", first.uuid.uuidString)
        }

        let id = peripheral.identifier
        lock.lock()
        if let wc = writeChar { writeCharMap[id] = wc }
        if let rc = reportChar { reportCharMap[id] = rc }
        lock.unlock()

        // Build HIDDeviceInfo and notify delegate
        let name = peripheral.name ?? "Logitech BLE Device"
        let serial = peripheral.identifier.uuidString
        let info = HIDDeviceInfo(
            vendorID: 0x046D,
            productID: 0xB034, // MX Master 3S BLE PID
            name: name,
            serialNumber: serial,
            transport: .bluetooth
        )

        lock.lock()
        connectedPeripherals[peripheral.identifier] = peripheral
        deviceInfoMap[peripheral.identifier] = info
        peripheralIDBySerial[serial] = peripheral.identifier
        updateConnectedDevices()
        lock.unlock()

        NSLog("[BLETransport] Device ready: %@ (write=%@, report=%@)",
              name,
              writeChar?.uuid.uuidString ?? "none",
              reportChar?.uuid.uuidString ?? "none")

        delegate?.transport(self, didConnectDevice: info)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                            didUpdateValueFor characteristic: CBCharacteristic,
                            error: Error?) {
        if let error {
            NSLog("[BLETransport] Read error: %@", error.localizedDescription)
            return
        }

        guard let data = characteristic.value, !data.isEmpty else { return }

        let hex = data.prefix(min(data.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[BLETransport] RX: %@", hex)

        guard let info = deviceInfoMap[peripheral.identifier] else {
            NSLog("[BLETransport] RX from unknown peripheral — ignoring")
            return
        }

        delegate?.transport(self, didReceiveReport: data, fromDevice: info)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                            didWriteValueFor characteristic: CBCharacteristic,
                            error: Error?) {
        if let error {
            NSLog("[BLETransport] Write error: %@", error.localizedDescription)
        }
    }
}

// MARK: - Errors

public enum BLETransportError: Error, CustomStringConvertible {
    case notConnected
    case noWriteCharacteristic
    case bluetoothNotReady

    public var description: String {
        switch self {
        case .notConnected: return "BLE device not connected"
        case .noWriteCharacteristic: return "No writable BLE characteristic found"
        case .bluetoothNotReady: return "Bluetooth not powered on or unauthorized"
        }
    }
}

// MARK: - CBCharacteristicProperties helpers

extension CBCharacteristicProperties {
    var debugDescription: String {
        var parts: [String] = []
        if contains(.broadcast) { parts.append("broadcast") }
        if contains(.read) { parts.append("read") }
        if contains(.writeWithoutResponse) { parts.append("writeWithoutResponse") }
        if contains(.write) { parts.append("write") }
        if contains(.notify) { parts.append("notify") }
        if contains(.indicate) { parts.append("indicate") }
        if contains(.authenticatedSignedWrites) { parts.append("authenticatedSignedWrites") }
        if contains(.extendedProperties) { parts.append("extendedProperties") }
        return parts.joined(separator: ", ")
    }
}
