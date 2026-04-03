import Foundation

extension MrMouseConfig {
    public static let `default` = MrMouseConfig(
        devices: [:],
        globalProfile: .default,
        appProfiles: [:],
        launchAtLogin: false
    )
}

extension DeviceConfig {
    public static let mxMaster3S = DeviceConfig(
        dpi: 1000,
        smartShiftEnabled: true,
        smartShiftThreshold: 30,
        hiResScrollEnabled: true,
        scrollInverted: false,
        thumbWheelInverted: false
    )

    public var dpiRange: ClosedRange<Int> { 200...8000 }
    public var dpiStep: Int { 50 }
    public var smartShiftRange: ClosedRange<Int> { 1...255 }
}
