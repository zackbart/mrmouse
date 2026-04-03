import SwiftUI
import Combine

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
    private let bleTransport = BLETransport()
    private let eventTap = EventTapManager()
    private let gestureRecognizer = GestureRecognizer()
    private let appProfileManager = AppProfileManager()

    /// Devices currently undergoing feature discovery — reports are forwarded to them
    /// so request-response correlation works before they join `devices`.
    /// Guarded by `discoveringDevicesLock`, accessed from multiple threads.
    private let discoveringDevicesLock = NSLock()
    nonisolated(unsafe) private var discoveringDevices: [HIDPPDevice] = []

    // MARK: - Init

    public init() {
        setupSubsystems()
    }

    // MARK: - Setup

    private func setupSubsystems() {
        transport.delegate = self
        bleTransport.delegate = self

        gestureRecognizer.onGesture = { [weak self] gestureType in
            guard let self else { return }
            NSLog("[AppState] Gesture recognized: %@", "\(gestureType)")
            let profile = self.configManager.profileForApp(self.currentApp)
            let action = profile.gestureActions.action(for: gestureType)
            NSLog("[AppState] Dispatching action: %@", "\(action)")
            ActionDispatcher.perform(action)
        }

        eventTap.buttonHandler = { [weak self] buttonNumber, isDown in
            guard let self else { return false }
            return self.handleButtonEvent(buttonNumber: buttonNumber, isDown: isDown)
        }

        // Feed mouse movement deltas into the gesture recognizer.
        // This is the primary source for gesture swipe detection — HID++ rawXY
        // is a fallback that may not fire on all firmware versions.
        eventTap.mouseMoveHandler = { [weak self] dx, dy in
            guard let self else { return }
            self.gestureRecognizer.addDelta(dx: dx, dy: dy)
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
        bleTransport.start()
    }

    // MARK: - Button event handling (from CGEventTap)

    private nonisolated func handleButtonEvent(buttonNumber: Int, isDown: Bool) -> Bool {
        // Button 5 = gesture button (MX Master 3S thumb button)
        if buttonNumber == 5 {
            if isDown {
                DispatchQueue.main.async {
                    self.gestureRecognizer.buttonDown()
                }
            } else {
                DispatchQueue.main.async {
                    self.gestureRecognizer.buttonUp()
                }
            }
            return true  // suppress so system doesn't trigger Mission Control etc.
        }
        return false  // pass through everything else
    }

    // MARK: - HID++ notification handling

    /// Previously-pressed diverted control IDs, used to detect press/release transitions.
    nonisolated(unsafe) private var previousDivertedCIDs: [UInt16] = [0, 0, 0, 0]

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
        NSLog("[AppState] handleDivertedButton called: fn=0x%02X params=%@",
              message.functionID,
              message.parameters.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))
        // ReprogControlsV4 notification format (per Solaar source):
        //   address 0x00 (fn 0x00): [cid1_be16, cid2_be16, cid3_be16, cid4_be16]
        //     — all currently-pressed diverted controls; diff against previous to detect transitions
        //   address 0x10 (fn 0x01): [dx_be16_signed, dy_be16_signed]
        //     — raw pointer deltas while a .rawXY button is held
        if message.functionID == 0x00, message.parameters.count >= 8 {
            let cids = (0..<4).map { i in
                UInt16(message.parameters[i * 2]) << 8 | UInt16(message.parameters[i * 2 + 1])
            }

            // Detect press: in new set but not in old set
            for cid in cids where cid != 0 && !previousDivertedCIDs.contains(cid) {
                if cid == 0x00C3 {
                    Task { @MainActor in
                        self.gestureRecognizer.buttonDown()
                    }
                } else {
                    let controlID = cid
                    Task { @MainActor in
                        let profile = self.configManager.profileForApp(self.currentApp)
                        if let mapping = profile.buttonMappings.first(where: { $0.controlID == controlID }) {
                            ActionDispatcher.perform(mapping.action)
                        }
                    }
                }
            }

            // Detect release: in old set but not in new set
            for oldCid in previousDivertedCIDs where oldCid != 0 && !cids.contains(oldCid) {
                if oldCid == 0x00C3 {
                    Task { @MainActor in
                        self.gestureRecognizer.buttonUp()
                    }
                }
            }

            previousDivertedCIDs = cids
        } else if message.functionID == 0x01, message.parameters.count >= 4 {
            // Raw XY delta
            let dx = CGFloat(Int16(message.parameters[0]) << 8 | Int16(message.parameters[1]))
            let dy = CGFloat(Int16(message.parameters[2]) << 8 | Int16(message.parameters[3]))
            Task { @MainActor in
                self.gestureRecognizer.addDelta(dx: dx, dy: dy)
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

        nonisolated(unsafe) let capturedTransport = transport
        DispatchQueue.global(qos: .userInitiated).async {
            if isReceiver {
                NSLog("[AppState] Receiver detected, probing device indices 1-6...")
                var foundDevices: [HIDPPDevice] = []

                for idx: UInt8 in 1...6 {
                    let device = HIDPPDevice(info: deviceInfo, transport: capturedTransport, deviceIndex: idx)

                    // Register so didReceiveReport forwards HID++ responses during discovery
                    self.discoveringDevicesLock.lock()
                    self.discoveringDevices.append(device)
                    self.discoveringDevicesLock.unlock()

                    do {
                        device.featureTable = [:]
                        try device.discoverFeatures()
                        NSLog("[AppState] Found device at receiver index %d (%d features)", idx, device.featureTable.count)
                        foundDevices.append(device)
                    } catch {
                        NSLog("[AppState] No device at receiver index %d: %@", idx, error.localizedDescription)
                    }

                    // Remove failed devices immediately; keep found ones for initialization
                    if !foundDevices.contains(where: { $0 === device }) {
                        self.discoveringDevicesLock.lock()
                        self.discoveringDevices.removeAll { $0 === device }
                        self.discoveringDevicesLock.unlock()
                    }
                }

                NSLog("[AppState] Found %d paired device(s) on receiver", foundDevices.count)
                for hidppDevice in foundDevices {
                    // Keep in discoveringDevices through initialization so report
                    // forwarding works for config writes (DPI, SmartShift, button diversion)
                    self.initializeDevice(hidppDevice, transportType: deviceInfo.transport)

                    self.discoveringDevicesLock.lock()
                    self.discoveringDevices.removeAll { $0 === hidppDevice }
                    self.discoveringDevicesLock.unlock()
                }
            } else {
                let hidppDevice = HIDPPDevice(info: deviceInfo, transport: capturedTransport)

                self.discoveringDevicesLock.lock()
                self.discoveringDevices.append(hidppDevice)
                self.discoveringDevicesLock.unlock()

                Self.discoverFeaturesWithRetry(device: hidppDevice, maxAttempts: 3, delay: 0.5)

                // Keep in discoveringDevices through initialization
                self.initializeDevice(hidppDevice, transportType: deviceInfo.transport)

                self.discoveringDevicesLock.lock()
                self.discoveringDevices.removeAll { $0 === hidppDevice }
                self.discoveringDevicesLock.unlock()
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
        // Forward to devices undergoing discovery (synchronous — they block on semaphore)
        discoveringDevicesLock.lock()
        let discovering = discoveringDevices
        discoveringDevicesLock.unlock()
        for dev in discovering {
            dev.handleReport(data)
        }

        Task { @MainActor in
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

        let hasReprog = device.hasFeature(HIDPPFeature.reprogControlsV4.rawValue)
        if hasReprog {
            // Log available controls first
            do {
                let count = try ReprogControls.getControlCount(device: device)
                NSLog("[AppState] ReprogControls: %d controls available", count)
                for i in 0..<min(count, 16) {
                    let info = try ReprogControls.getControlInfo(device: device, index: i)
                    NSLog("[AppState]   control[%d]: id=0x%04X task=0x%04X flags=0x%04X",
                          i, info.controlID, info.taskID, info.flags)
                }
            } catch {
                NSLog("[AppState] ReprogControls enumeration failed: %@", error.localizedDescription)
            }

            let profile = configManager.profileForApp(nil)
            for mapping in profile.buttonMappings where mapping.diverted {
                // First read current reporting to see what the device says
                do {
                    let current = try ReprogControls.getControlReporting(device: device, controlID: mapping.controlID)
                    NSLog("[AppState] Current reporting for 0x%04X: remapped=0x%04X flags=0x%02X",
                          mapping.controlID, current.remapped, current.flags.rawValue)
                } catch {
                    NSLog("[AppState] getControlReporting for 0x%04X failed: %@",
                          mapping.controlID, error.localizedDescription)
                }
                // Try diversion with .divert + .rawXY first
                do {
                    let reporting = ControlReporting(
                        remapped: mapping.controlID,
                        flags: [.divert, .rawXY]
                    )
                    try ReprogControls.setControlReporting(
                        device: device,
                        controlID: mapping.controlID,
                        reporting: reporting
                    )
                } catch {
                    NSLog("[AppState] setControlReporting [.divert,.rawXY] failed for 0x%04X: %@",
                          mapping.controlID, error.localizedDescription)
                }
                // Verify what the device actually accepted
                do {
                    let after = try ReprogControls.getControlReporting(device: device, controlID: mapping.controlID)
                    NSLog("[AppState] After diversion for 0x%04X: remapped=0x%04X flags=0x%02X",
                          mapping.controlID, after.remapped, after.flags.rawValue)
                } catch {
                    NSLog("[AppState] verify getControlReporting for 0x%04X failed: %@",
                          mapping.controlID, error.localizedDescription)
                }
                // Also try with .divert + .rawXY + .force (device supports force per flags=0x3100)
                do {
                    let reporting = ControlReporting(
                        remapped: mapping.controlID,
                        flags: [.divert, .rawXY, .force]
                    )
                    try ReprogControls.setControlReporting(
                        device: device,
                        controlID: mapping.controlID,
                        reporting: reporting
                    )
                    NSLog("[AppState] setControlReporting [.divert,.rawXY,.force] OK for 0x%04X",
                          mapping.controlID)
                } catch {
                    NSLog("[AppState] setControlReporting [.divert,.rawXY,.force] failed for 0x%04X: %@",
                          mapping.controlID, error.localizedDescription)
                }
                // Verify again
                do {
                    let afterForce = try ReprogControls.getControlReporting(device: device, controlID: mapping.controlID)
                    NSLog("[AppState] After force diversion for 0x%04X: remapped=0x%04X flags=0x%02X",
                          mapping.controlID, afterForce.remapped, afterForce.flags.rawValue)
                } catch {
                    NSLog("[AppState] verify force getControlReporting for 0x%04X failed: %@",
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
