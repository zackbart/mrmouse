import Foundation
import IOKit
import IOKit.hid

// MARK: - Logitech Constants

private let kLogitechVID: Int = 0x046D

/// Known Logitech product IDs used for matching and transport-type classification.
private enum LogitechPID {
    // Bluetooth PIDs — MX Master family
    static let mxMaster3SBluetooth: Int = 0xB023
    static let mxMaster3SBLE:      Int = 0xB034  // MX Master 3S via BLE
    static let mxMaster3Bluetooth:  Int = 0x4082
    static let mxMaster2SBluetooth: Int = 0xB012
    static let mxMasterBluetooth:   Int = 0xB006

    // USB receiver PIDs
    static let unifyingReceiver: Int = 0xC52B
    static let boltReceiver:     Int = 0xC548

    // BLE PIDs — may have different VendorIDSource on macOS
    static let mxMaster3SBLEAlt: Int = 45108   // 0xB034 as reported by IOKit for BLE

    static let bluetoothPIDs: Set<Int> = [
        mxMaster3SBluetooth,
        mxMaster3SBLE,
        mxMaster3Bluetooth,
        mxMaster2SBluetooth,
        mxMasterBluetooth,
        mxMaster3SBLEAlt,
    ]

    // PIDs to match without VID (BLE devices may not report USB VID)
    static let blePIDs: Set<Int> = [
        mxMaster3SBLE,
        mxMaster3SBLEAlt,
    ]

    static let unifyingPIDs: Set<Int> = [unifyingReceiver]
    static let boltPIDs:     Set<Int> = [boltReceiver]
}

// MARK: - HID report buffer size

private let kHIDReportBufferSize: Int = 64

// MARK: - HIDTransport

/// Concrete IOKit HID transport for Logitech HID++ devices.
///
/// All IOKit callbacks fire on a dedicated background thread that owns a private
/// CFRunLoop.  Delegate notifications are always dispatched to the main queue.
public final class HIDTransport: HIDTransportProtocol {

    // MARK: Public interface

    public weak var delegate: HIDTransportDelegate?

    public var connectedDevices: [HIDDeviceInfo] {
        lock.lock(); defer { lock.unlock() }
        return deviceMap.values.map(\.info)
    }

    // MARK: Private state

    // Key: a stable integer derived from the IOHIDDevice pointer value.
    private var deviceMap: [Int: DeviceState] = [:]
    // Track which physical devices we've already notified about (VID-PID-serial).
    private var notifiedDevices: Set<String> = []
    private let lock = NSLock()

    private var manager: IOHIDManager?
    private var hidThread: HIDRunLoopThread?

    // MARK: Init / deinit

    public init() {}

    deinit {
        stop()
    }

    // MARK: - HIDTransportProtocol

    public func start() {
        guard hidThread == nil else { return }

        let thread = HIDRunLoopThread()
        thread.qualityOfService = .userInteractive
        hidThread = thread
        thread.start()

        // Wait on a background queue to avoid priority inversion on the main thread
        DispatchQueue.global(qos: .userInteractive).async {
            thread.waitUntilReady()
            thread.perform { [weak self] in
                guard let self, let rl = thread.cfRunLoop else { return }
                self.setupManager(runLoop: rl)
            }
        }
    }

    public func stop() {
        guard let thread = hidThread else { return }
        hidThread = nil

        thread.perform { [weak self] in
            guard let self else { return }
            if let mgr = self.manager {
                IOHIDManagerUnscheduleFromRunLoop(
                    mgr,
                    CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue
                )
                IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
                self.manager = nil
            }
        }

        thread.cancel()

        lock.lock()
        deviceMap.removeAll()
        notifiedDevices.removeAll()
        lock.unlock()
    }

    public func sendReport(_ data: Data, to device: HIDDeviceInfo) throws {
        guard data.count >= 1 else {
            throw HIDPPDeviceError.transportError("Empty report data")
        }

        lock.lock()
        let matchingStates = deviceMap.values.filter {
            $0.info.vendorID == device.vendorID && $0.info.productID == device.productID
        }
        lock.unlock()

        guard !matchingStates.isEmpty else {
            throw HIDPPDeviceError.deviceNotFound
        }

        let reportID = CFIndex(data[0])

        // Prefer vendor HID++ interfaces (0xFF00, 0xFF43) over standard HID (0x0001).
        let sorted = matchingStates.sorted { a, b in
            let aVendor = a.usagePage >= 0xFF00
            let bVendor = b.usagePage >= 0xFF00
            if aVendor != bVendor { return aVendor }
            return false
        }

        var lastError: IOReturn = kIOReturnSuccess
        var sent = false

        for state in sorted {
            // macOS IOKit requires report ID included in the data buffer for SetReport
            let result: IOReturn = data.withUnsafeBytes { ptr -> IOReturn in
                guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(
                    state.device,
                    kIOHIDReportTypeOutput,
                    reportID,
                    base.assumingMemoryBound(to: UInt8.self),
                    CFIndex(data.count)
                )
            }

            if result == kIOReturnSuccess {
                sent = true
                break
            } else {
                lastError = result
            }
        }

        if !sent {
            throw HIDPPDeviceError.transportError(
                String(format: "IOHIDDeviceSetReport failed on all %d interfaces: 0x%08X",
                       sorted.count, lastError)
            )
        }
    }

    // MARK: - Manager setup (HID thread)

    private func setupManager(runLoop: CFRunLoop) {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = mgr

        IOHIDManagerSetDeviceMatchingMultiple(mgr, buildMatchingArray() as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, deviceMatchingCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, deviceRemovalCallback, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, runLoop, CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            NSLog("[HIDTransport] IOHIDManagerOpen returned 0x%08X", openResult)
        }
    }

    // MARK: - Matching dictionaries

    private func buildMatchingArray() -> [[String: Any]] {
        var dicts: [[String: Any]] = []

        // Explicit VID+PID for every known Bluetooth MX Master PID.
        for pid in LogitechPID.bluetoothPIDs {
            dicts.append(pidMatchDict(pid: pid))
        }

        // BLE devices may report PID differently — also match by PID alone
        // (without VID constraint) for known BLE PIDs
        for pid in LogitechPID.blePIDs {
            dicts.append([kIOHIDProductIDKey as String: pid])
        }

        // Unifying and Bolt receivers.
        dicts.append(pidMatchDict(pid: LogitechPID.unifyingReceiver))
        dicts.append(pidMatchDict(pid: LogitechPID.boltReceiver))

        // Logitech vendor usage page 0xFF00 (USB HID++)
        dicts.append([
            kIOHIDVendorIDKey as String:        kLogitechVID,
            kIOHIDPrimaryUsagePageKey as String: 0xFF00,
        ])

        // Logitech BLE vendor usage page 0xFF43 (BLE HID++)
        dicts.append([
            kIOHIDPrimaryUsagePageKey as String: 0xFF43,
        ])

        // Catch-all: any Logitech VID device
        dicts.append([
            kIOHIDVendorIDKey as String: kLogitechVID,
        ])

        return dicts
    }

    private func pidMatchDict(pid: Int) -> [String: Any] {
        [
            kIOHIDVendorIDKey as String:  kLogitechVID,
            kIOHIDProductIDKey as String: pid,
        ]
    }

    // MARK: - Device connect / disconnect (HID thread)

    fileprivate func handleDeviceMatched(_ device: IOHIDDevice) {
        let vid    = intProperty(of: device, key: kIOHIDVendorIDKey) ?? 0
        let pid    = intProperty(of: device, key: kIOHIDProductIDKey) ?? 0
        let name   = stringProperty(of: device, key: kIOHIDProductKey) ?? "Unknown Device"
        let serial = stringProperty(of: device, key: kIOHIDSerialNumberKey)
        let transportStr = stringProperty(of: device, key: kIOHIDTransportKey) ?? "unknown"
        let usagePage = intProperty(of: device, key: kIOHIDPrimaryUsagePageKey) ?? 0
        let usage = intProperty(of: device, key: kIOHIDPrimaryUsageKey) ?? 0

        NSLog("[HIDTransport] Device matched: '%@' VID=0x%04X PID=0x%04X transport=%@ usagePage=0x%04X usage=0x%04X serial=%@",
              name, vid, pid, transportStr, usagePage, usage, serial ?? "none")
        let xport  = resolveTransportType(pid: pid, device: device)

        let info = HIDDeviceInfo(
            vendorID: vid,
            productID: pid,
            name: name,
            serialNumber: serial,
            transport: xport
        )

        // Seize vendor interfaces (0xFF00) to bypass kernel notification filtering.
        // Standard HID interfaces (keyboard/mouse) are opened normally.
        let isVendorInterface = (usagePage == 0xFF00)
        let openOptions: IOOptionBits = isVendorInterface
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)

        var didSeize = isVendorInterface
        var openResult = IOHIDDeviceOpen(device, openOptions)
        if openResult != kIOReturnSuccess {
            if isVendorInterface {
                NSLog("[HIDTransport] Seize failed (0x%08X), falling back to normal open for '%@'",
                      openResult, name)
                didSeize = false
                openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            if openResult != kIOReturnSuccess {
                NSLog("[HIDTransport] IOHIDDeviceOpen failed (0x%08X) for '%@' usagePage=0x%04X",
                      openResult, name, usagePage)
                return
            }
        }
        NSLog("[HIDTransport] IOHIDDeviceOpen %@ for '%@' usagePage=0x%04X usage=0x%04X",
              didSeize ? "SEIZED" : "OK", name, usagePage, usage)

        let state = DeviceState(device: device, info: info, usagePage: usagePage, transport: self)
        let key   = deviceKey(for: device)

        lock.lock()
        deviceMap[key] = state
        lock.unlock()

        // Register input callback on ALL interfaces — HID++ reports may arrive
        // on the vendor interface (0xFF00) while standard mouse reports arrive on 0x0001.
        let stateCtx = Unmanaged.passUnretained(state).toOpaque()
        state.reportBuffer.withUnsafeMutableBytes { bufPtr in
            guard let base = bufPtr.baseAddress else { return }
            IOHIDDeviceRegisterInputReportCallback(
                device,
                base.assumingMemoryBound(to: UInt8.self),
                CFIndex(kHIDReportBufferSize),
                inputReportCallback,
                stateCtx
            )
        }

        // Only notify delegate once per physical device.
        let dedupeKey = "\(vid)-\(pid)-\(serial ?? "none")"
        lock.lock()
        let alreadyNotified = notifiedDevices.contains(dedupeKey)
        if !alreadyNotified { notifiedDevices.insert(dedupeKey) }
        lock.unlock()

        guard !alreadyNotified else {
            NSLog("[HIDTransport] Skipping duplicate for '%@' (%@)", name, dedupeKey)
            return
        }

        let capturedDelegate = delegate
        let capturedSelf = self
        DispatchQueue.main.async {
            capturedDelegate?.transport(capturedSelf, didConnectDevice: info)
        }
    }

    fileprivate func handleDeviceRemoved(_ device: IOHIDDevice) {
        let key = deviceKey(for: device)

        lock.lock()
        let state = deviceMap.removeValue(forKey: key)
        // Remove from dedup set so reconnection fires a new notification.
        if let state {
            let vid = state.info.vendorID
            let pid = state.info.productID
            let serial = state.info.serialNumber ?? "none"
            let dedupeKey = "\(vid)-\(pid)-\(serial)"
            // Only remove from notifiedDevices if no other interfaces remain for this physical device.
            let hasOtherInterfaces = deviceMap.values.contains { s in
                s.info.vendorID == vid && s.info.productID == pid &&
                (s.info.serialNumber ?? "none") == serial
            }
            if !hasOtherInterfaces {
                notifiedDevices.remove(dedupeKey)
            }
        }
        lock.unlock()

        guard let state else { return }

        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))

        let capturedDelegate = delegate
        let capturedSelf = self
        let info = state.info
        DispatchQueue.main.async {
            capturedDelegate?.transport(capturedSelf, didDisconnectDevice: info)
        }
    }

    // Dedup: track last HID++ report to avoid forwarding duplicates from multiple interfaces
    private var lastHIDPPReport: Data?

    fileprivate func handleInputReport(
        from state: DeviceState,
        reportType: IOHIDReportType,
        reportID: UInt32,
        bytes: UnsafeMutablePointer<UInt8>,
        length: CFIndex
    ) {
        guard length > 0 else { return }

        // Build report data with report ID as first byte.
        // On some macOS versions the callback buffer already includes the report ID;
        // on others it doesn't.  Detect by checking if byte 0 matches reportID.
        let reportData: Data
        if length > 0, bytes[0] == UInt8(reportID & 0xFF) {
            reportData = Data(bytes: bytes, count: Int(length))
        } else {
            var data = Data(count: Int(length) + 1)
            data[0] = UInt8(reportID & 0xFF)
            data.withUnsafeMutableBytes { dest in
                guard let destBase = dest.baseAddress else { return }
                memcpy(destBase.advanced(by: 1), bytes, Int(length))
            }
            reportData = data
        }

        let rid = reportData[0]

        // DIAGNOSTIC: log all reports arriving on vendor interfaces after init
        let up = state.usagePage
        if rid == 0x10 || rid == 0x11 {
            let hex = reportData.prefix(min(reportData.count, 20)).map { String(format: "%02X", $0) }.joined(separator: " ")
            NSLog("[HIDTransport] RX HID++ report: usagePage=0x%04X len=%d rid=0x%02X data=[%@]",
                  up, reportData.count, rid, hex)
        } else {
            NSLog("[HIDTransport] RX non-HID++ report: usagePage=0x%04X len=%d rid=0x%02X",
                  up, reportData.count, rid)
        }

        // Deduplicate HID++ reports (0x10/0x11) — multiple interfaces fire for the same report.
        // Use content comparison only; discard exact byte-for-byte duplicates of the previous report.
        if rid == 0x10 || rid == 0x11 {
            lock.lock()
            let isDuplicate = (reportData == lastHIDPPReport)
            lastHIDPPReport = reportData
            lock.unlock()

            if isDuplicate {
                NSLog("[HIDTransport] Deduped duplicate HID++ report")
                return
            }
        }

        let info = state.info
        let capturedDelegate = delegate
        let capturedSelf = self
        DispatchQueue.main.async {
            capturedDelegate?.transport(capturedSelf, didReceiveReport: reportData, fromDevice: info)
        }
    }

    // MARK: - Transport type resolution

    private func resolveTransportType(pid: Int, device: IOHIDDevice) -> HIDDeviceInfo.TransportType {
        // PID-first classification is most reliable.
        if LogitechPID.bluetoothPIDs.contains(pid) { return .bluetooth }
        if LogitechPID.boltPIDs.contains(pid)       { return .bolt }
        if LogitechPID.unifyingPIDs.contains(pid)   { return .unifying }

        // Fall back to IOKit transport property.
        if let t = stringProperty(of: device, key: kIOHIDTransportKey) {
            switch t.lowercased() {
            case "bluetooth", "bluetooth low energy", "bluetoothlowenergy", "ble":
                return .bluetooth
            case "usb":
                if pid == LogitechPID.boltReceiver      { return .bolt }
                if pid == LogitechPID.unifyingReceiver  { return .unifying }
            default: break
            }
        }

        return .usb
    }

    // MARK: - IOKit property helpers

    private func intProperty(of device: IOHIDDevice, key: String) -> Int? {
        guard let val = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        if let n = val as? Int    { return n }
        if let n = val as? NSNumber { return n.intValue }
        return nil
    }

    private func stringProperty(of device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    // MARK: - Stable key for IOHIDDevice

    /// Derive a stable dictionary key from the IOHIDDevice CF reference.
    private func deviceKey(for device: IOHIDDevice) -> Int {
        // IOHIDDevice is a CF type; its pointer value is unique during its lifetime.
        Int(bitPattern: ObjectIdentifier(device as AnyObject))
    }
}

// MARK: - DeviceState

/// Mutable per-device state owned exclusively by `HIDTransport.deviceMap`.
final class DeviceState {
    let device: IOHIDDevice
    let info: HIDDeviceInfo
    let usagePage: Int
    /// Buffer passed to `IOHIDDeviceRegisterInputReportCallback`.
    /// Must not be moved or deallocated while the callback is registered.
    var reportBuffer: [UInt8]
    /// Weak reference back to the owning transport, used inside the C callback.
    weak var transport: HIDTransport?

    init(device: IOHIDDevice, info: HIDDeviceInfo, usagePage: Int, transport: HIDTransport) {
        self.device = device
        self.info = info
        self.usagePage = usagePage
        self.reportBuffer = [UInt8](repeating: 0, count: kHIDReportBufferSize)
        self.transport = transport
    }
}

// MARK: - C Callbacks

/// Device matching callback — fires on the HID run loop thread.
private let deviceMatchingCallback: IOHIDDeviceCallback = {
    context, result, sender, device in
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
        .handleDeviceMatched(device)
}

/// Device removal callback — fires on the HID run loop thread.
private let deviceRemovalCallback: IOHIDDeviceCallback = {
    context, result, sender, device in
    guard let context else { return }
    Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
        .handleDeviceRemoved(device)
}

/// Input report callback — fires on the HID run loop thread.
///
/// `context` points to the `DeviceState` for the reporting device.  The state
/// holds a weak reference to its owning `HIDTransport`.
private let inputReportCallback: IOHIDReportCallback = {
    context, result, sender, reportType, reportID, report, reportLength in
    guard result == kIOReturnSuccess,
          let context
    else { return }

    let state = Unmanaged<DeviceState>.fromOpaque(context).takeUnretainedValue()
    state.transport?.handleInputReport(
        from: state,
        reportType: reportType,
        reportID: reportID,
        bytes: report,
        length: reportLength
    )
}

// MARK: - HIDRunLoopThread

/// Background `Thread` subclass that owns and spins a `CFRunLoop`.
/// All IOKit callbacks for the HID manager are delivered on this thread.
private final class HIDRunLoopThread: Thread {

    private(set) var cfRunLoop: CFRunLoop?
    private let readySemaphore = DispatchSemaphore(value: 0)

    /// Wait until `main()` has obtained the run loop reference.
    func waitUntilReady() {
        readySemaphore.wait()
    }

    /// Schedule `block` on the HID run loop (asynchronous w.r.t. the caller).
    func perform(_ block: @escaping () -> Void) {
        guard let rl = cfRunLoop else {
            // Should not happen after waitUntilReady() has returned.
            assertionFailure("[HIDRunLoopThread] perform called before run loop is ready")
            return
        }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    override func main() {
        // Capture the run loop reference before signalling the semaphore so
        // callers of waitUntilReady() always see a non-nil cfRunLoop.
        cfRunLoop = CFRunLoopGetCurrent()
        readySemaphore.signal()

        // A CFRunLoopSource with no callbacks keeps the run loop from exiting
        // when there are no other sources pending.
        var sourceCtx = CFRunLoopSourceContext()
        sourceCtx.version = 0
        let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceCtx)
        CFRunLoopAddSource(cfRunLoop, keepAliveSource, CFRunLoopMode.defaultMode)

        while !isCancelled {
            // Run for up to 0.5 s then check isCancelled; IOKit callbacks fire
            // in between without waiting for the timeout.
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.5, false)
        }

        CFRunLoopRemoveSource(cfRunLoop, keepAliveSource, CFRunLoopMode.defaultMode)
    }
}
