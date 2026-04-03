import SwiftUI
@preconcurrency import HIDPPCore
import EventEngine
import Config

/// Snapshot of a connected device's state, published for the UI.
public struct ConnectedDevice: Identifiable {
    public let id: String               // unique key: serialNumber or "name-transport-index"
    public let name: String
    public let transport: HIDDeviceInfo.TransportType
    public var batteryLevel: Int?
    public var batteryCharging: Bool = false
    public var firmwareVersion: String?
    public var currentDPI: Int = 1000
    let hidppDevice: HIDPPDevice        // internal, not for the UI
}

/// Central observable state for the menu bar UI.
/// Owns and coordinates HIDPPCore, EventEngine, and Config layers.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Multi-device state

    @Published public var devices: [ConnectedDevice] = []
    @Published public var selectedDeviceID: String? = nil

    /// The currently selected device for settings changes.
    public var selectedDevice: ConnectedDevice? {
        guard let id = selectedDeviceID else { return devices.first }
        return devices.first(where: { $0.id == id }) ?? devices.first
    }

    /// Convenience: is anything connected?
    public var isConnected: Bool { !devices.isEmpty }

    // MARK: - Active app

    @Published public var currentApp: String? = nil

    // MARK: - Config

    public let configManager: ConfigManager = .shared

    // MARK: - Private subsystems

    private let transport = HIDTransport()
    private let eventTap = EventTapManager()
    private let gestureRecognizer = GestureRecognizer()
    private let appProfileManager = AppProfileManager()

    // MARK: - Init

    public init() {
        setupSubsystems()
    }

    // MARK: - Setup

    private func setupSubsystems() {
        transport.delegate = self

        gestureRecognizer.onGesture = { [weak self] gestureType in
            guard let self else { return }
            let profile = self.configManager.profileForApp(self.currentApp)
            let action = profile.gestureActions.action(for: gestureType)
            ActionDispatcher.perform(action)
        }

        eventTap.buttonHandler = { [weak self] buttonNumber, isDown in
            guard let self else { return nil }
            return self.handleButtonEvent(buttonNumber: buttonNumber, isDown: isDown)
        }

        appProfileManager.onAppChanged = { [weak self] bundleID in
            guard let self else { return }
            Task { @MainActor in
                self.currentApp = bundleID
            }
        }

        currentApp = appProfileManager.currentBundleID

        appProfileManager.start()
        eventTap.start()
        transport.start()
    }

    // MARK: - Button event handling (from CGEventTap)

    private func handleButtonEvent(buttonNumber: Int, isDown: Bool) -> CGEvent? {
        return nil
    }

    // MARK: - HID++ notification handling

    nonisolated private func handleNotification(_ message: HIDPPMessage, device: HIDPPDevice) {
        if let batteryIdx = device.featureTable[HIDPPFeature.unifiedBattery.rawValue],
           message.featureIndex == batteryIdx {
            if let status = UnifiedBattery.parse(notification: message) {
                Task { @MainActor in
                    self.updateDevice(device) { dev in
                        dev.batteryLevel = status.percentage
                        dev.batteryCharging = status.charging
                    }
                }
            }
            return
        }

        if let reprogIdx = device.featureTable[HIDPPFeature.reprogControlsV4.rawValue],
           message.featureIndex == reprogIdx {
            handleDivertedButton(message: message)
            return
        }
    }

    nonisolated private func handleDivertedButton(message: HIDPPMessage) {
        guard message.parameters.count >= 3 else { return }
        let controlID = UInt16(message.parameters[0]) << 8 | UInt16(message.parameters[1])
        let isPressed = message.parameters[2] != 0

        if controlID == 0x00C3 {
            Task { @MainActor in
                if isPressed {
                    self.gestureRecognizer.buttonDown()
                } else {
                    self.gestureRecognizer.buttonUp()
                }
            }
            return
        }

        guard isPressed else { return }
        Task { @MainActor in
            let profile = self.configManager.profileForApp(self.currentApp)
            if let mapping = profile.buttonMappings.first(where: { $0.controlID == controlID }) {
                ActionDispatcher.perform(mapping.action)
            }
        }
    }

    // MARK: - Device list management

    private func addDevice(_ device: ConnectedDevice) {
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
        } else {
            devices.append(device)
        }
        // Auto-select if it's the only device
        if selectedDeviceID == nil {
            selectedDeviceID = device.id
        }
    }

    private func removeDevice(matching info: HIDDeviceInfo) {
        devices.removeAll { dev in
            dev.hidppDevice.info.vendorID == info.vendorID &&
            dev.hidppDevice.info.productID == info.productID
        }
        if let sel = selectedDeviceID, !devices.contains(where: { $0.id == sel }) {
            selectedDeviceID = devices.first?.id
        }
    }

    private func updateDevice(_ hidppDevice: HIDPPDevice, mutation: (inout ConnectedDevice) -> Void) {
        if let idx = devices.firstIndex(where: { $0.hidppDevice === hidppDevice }) {
            mutation(&devices[idx])
        }
    }

    /// The HIDPPDevice for the currently selected device.
    var activeHIDPPDevice: HIDPPDevice? {
        selectedDevice?.hidppDevice
    }

    // MARK: - Public UI-facing methods

    public func setDPI(_ dpi: Int) {
        guard let device = activeHIDPPDevice else { return }
        updateDevice(device) { $0.currentDPI = dpi }
        let key = device.info.serialNumber ?? device.info.name
        try? configManager.update { config in
            var dev = config.devices[key] ?? DeviceConfig()
            dev.dpi = dpi
            config.devices[key] = dev
        }
        DispatchQueue.global(qos: .userInitiated).async {
            try? AdjustableDPI.setDPI(device: device, sensor: 0, dpi: dpi)
        }
    }

    public func setSmartShift(enabled: Bool, threshold: Int) {
        guard let device = activeHIDPPDevice else { return }
        let key = device.info.serialNumber ?? device.info.name
        try? configManager.update { config in
            var dev = config.devices[key] ?? DeviceConfig()
            dev.smartShiftEnabled = enabled
            dev.smartShiftThreshold = threshold
            config.devices[key] = dev
        }
        let clampedThreshold = Swift.max(0, Swift.min(threshold, 255))
        DispatchQueue.global(qos: .userInitiated).async {
            let config = SmartShiftConfig(
                enabled: enabled,
                autoDisengageThreshold: UInt8(clampedThreshold)
            )
            try? SmartShift.setConfig(device: device, config: config)
        }
    }
}

// MARK: - HIDTransportDelegate

extension AppState: HIDTransportDelegate {

    public nonisolated func transport(
        _ transport: any HIDTransportProtocol,
        didConnectDevice deviceInfo: HIDDeviceInfo
    ) {
        NSLog("[AppState] Device connected: %@ (PID 0x%04X, transport: %@)",
              deviceInfo.name, deviceInfo.productID, deviceInfo.transport.rawValue)

        let isReceiver = deviceInfo.transport == .unifying || deviceInfo.transport == .bolt

        DispatchQueue.global(qos: .userInitiated).async {
            if isReceiver {
                NSLog("[AppState] Receiver detected, enumerating paired devices...")
                let pairedDevices = ReceiverEnumerator.createDevicesForReceiver(
                    receiverInfo: deviceInfo,
                    transport: transport
                )
                NSLog("[AppState] Found %d paired device(s) on receiver", pairedDevices.count)
                for hidppDevice in pairedDevices {
                    self.initializeDevice(hidppDevice, transportType: deviceInfo.transport)
                }
            } else {
                let hidppDevice = HIDPPDevice(info: deviceInfo, transport: transport)
                Self.discoverFeaturesWithRetry(device: hidppDevice, maxAttempts: 3, delay: 0.5)
                self.initializeDevice(hidppDevice, transportType: deviceInfo.transport)
            }
        }
    }

    /// Retry feature discovery for devices that return transient errors (hwError / timeout)
    /// when waking from sleep. Clears partial state between attempts.
    nonisolated private static func discoverFeaturesWithRetry(
        device: HIDPPDevice,
        maxAttempts: Int,
        delay: TimeInterval
    ) {
        for attempt in 1...maxAttempts {
            // Reset feature table so a retry starts clean
            device.featureTable = [:]

            do {
                try device.discoverFeatures()
                NSLog("[AppState] Feature discovery succeeded on attempt %d (%d features)",
                      attempt, device.featureTable.count)
                return
            } catch let error as HIDPPError where error == .hwError || error == .busy {
                NSLog("[AppState] Feature discovery attempt %d/%d failed (retryable): %@",
                      attempt, maxAttempts, error.description)
            } catch let error as HIDPPDeviceError where error.isTimeout {
                NSLog("[AppState] Feature discovery attempt %d/%d timed out",
                      attempt, maxAttempts)
            } catch {
                NSLog("[AppState] Feature discovery attempt %d/%d failed (non-retryable): %@",
                      attempt, maxAttempts, error.localizedDescription)
                return
            }

            if attempt < maxAttempts {
                Thread.sleep(forTimeInterval: delay)
            }
        }
        NSLog("[AppState] Feature discovery failed after %d attempts", maxAttempts)
    }

    nonisolated private func initializeDevice(_ hidppDevice: HIDPPDevice, transportType: HIDDeviceInfo.TransportType) {
        hidppDevice.onNotification = { [weak self] message in
            guard let self else { return }
            self.handleNotification(message, device: hidppDevice)
        }

        var resolvedName = hidppDevice.info.name
        if hidppDevice.hasFeature(HIDPPFeature.deviceName.rawValue) {
            if let name = try? DeviceInfo.getDeviceName(device: hidppDevice), !name.isEmpty {
                resolvedName = name
            }
        }

        var fwString: String? = nil
        if hidppDevice.hasFeature(HIDPPFeature.deviceFWVersion.rawValue) {
            if let fw = try? DeviceInfo.getFirmwareVersion(device: hidppDevice) {
                fwString = "\(fw.version.major).\(fw.version.minor).\(fw.build)"
            }
        }

        var battery: BatteryStatus? = nil
        if hidppDevice.hasFeature(HIDPPFeature.unifiedBattery.rawValue) {
            battery = try? UnifiedBattery.getStatus(device: hidppDevice)
        }

        var dpi: Int = 1000
        if hidppDevice.hasFeature(HIDPPFeature.adjustableDPI.rawValue) {
            dpi = (try? AdjustableDPI.getDPI(device: hidppDevice, sensor: 0).dpi) ?? 1000
        }

        Self.applyDeviceConfigBackground(device: hidppDevice, configManager: ConfigManager.shared)

        let deviceID = hidppDevice.info.serialNumber
            ?? "\(resolvedName)-\(transportType.rawValue)"

        let connectedDevice = ConnectedDevice(
            id: deviceID,
            name: resolvedName,
            transport: transportType,
            batteryLevel: battery?.percentage,
            batteryCharging: battery?.charging ?? false,
            firmwareVersion: fwString,
            currentDPI: dpi,
            hidppDevice: hidppDevice
        )

        NSLog("[AppState] Device initialized: %@ via %@ (features: %d)",
              resolvedName, transportType.rawValue, hidppDevice.featureTable.count)

        Task { @MainActor in
            self.addDevice(connectedDevice)
        }
    }

    public nonisolated func transport(
        _ transport: any HIDTransportProtocol,
        didDisconnectDevice deviceInfo: HIDDeviceInfo
    ) {
        NSLog("[AppState] Device disconnected: %@", deviceInfo.name)
        Task { @MainActor in
            self.removeDevice(matching: deviceInfo)
        }
    }

    public nonisolated func transport(
        _ transport: any HIDTransportProtocol,
        didReceiveReport data: Data,
        fromDevice deviceInfo: HIDDeviceInfo
    ) {
        Task { @MainActor in
            // Forward to all devices — each checks its own device index
            for dev in self.devices {
                dev.hidppDevice.handleReport(data)
            }
        }
    }

    nonisolated private static func applyDeviceConfigBackground(device: HIDPPDevice,
                                                              configManager: ConfigManager) {
        let key = device.info.serialNumber ?? device.info.name
        let config = configManager.deviceConfig(for: key)

        if device.hasFeature(HIDPPFeature.adjustableDPI.rawValue) {
            do {
                try AdjustableDPI.setDPI(device: device, sensor: 0, dpi: config.dpi)
            } catch {
                NSLog("[AppState] setDPI failed: %@", error.localizedDescription)
            }
        }

        if device.hasFeature(HIDPPFeature.smartShift.rawValue) {
            do {
                let clampedThreshold = Swift.max(0, Swift.min(config.smartShiftThreshold, 255))
                let ssConfig = SmartShiftConfig(
                    enabled: config.smartShiftEnabled,
                    autoDisengageThreshold: UInt8(clampedThreshold)
                )
                try SmartShift.setConfig(device: device, config: ssConfig)
            } catch {
                NSLog("[AppState] setSmartShift failed: %@", error.localizedDescription)
            }
        }

        if device.hasFeature(HIDPPFeature.hiResWheel.rawValue) {
            do {
                let mode = HiResWheelMode(
                    hiRes: config.hiResScrollEnabled,
                    invert: config.scrollInverted,
                    target: false
                )
                try HiResWheel.setMode(device: device, mode: mode)
            } catch {
                NSLog("[AppState] setHiResWheel failed: %@", error.localizedDescription)
            }
        }

        if device.hasFeature(HIDPPFeature.reprogControlsV4.rawValue) {
            let profile = configManager.profileForApp(nil)
            for mapping in profile.buttonMappings where mapping.diverted {
                do {
                    let reporting = ControlReporting(
                        remapped: mapping.controlID,
                        flags: [.divert]
                    )
                    try ReprogControls.setControlReporting(
                        device: device,
                        controlID: mapping.controlID,
                        reporting: reporting
                    )
                } catch {
                    NSLog("[AppState] setControlReporting failed for 0x%04X: %@",
                          mapping.controlID, error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - GestureActions helper

private extension GestureActions {
    func action(for gesture: GestureType) -> ButtonAction {
        switch gesture {
        case .tap:        return tap
        case .swipeUp:    return swipeUp
        case .swipeDown:  return swipeDown
        case .swipeLeft:  return swipeLeft
        case .swipeRight: return swipeRight
        }
    }
}
