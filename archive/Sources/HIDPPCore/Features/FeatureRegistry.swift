import Foundation

/// Resolves and caches feature indices for a device.
/// Wraps `device.getFeatureIndex(featureID:)` with typed `HIDPPFeature` enum values.
public enum FeatureRegistry {

    /// Returns the runtime feature index for the given feature on the device.
    /// The index is cached inside `HIDPPDevice.featureTable` after the first lookup.
    ///
    /// - Parameters:
    ///   - feature: The well-known feature to look up.
    ///   - device: The target device.
    /// - Returns: The runtime 8-bit feature index.
    /// - Throws: `HIDPPDeviceError.featureNotSupported` if the device does not implement
    ///           the feature, or any transport/timeout error from the underlying request.
    public static func index(for feature: HIDPPFeature, on device: HIDPPDevice) throws -> UInt8 {
        try device.getFeatureIndex(featureID: feature.rawValue)
    }
}
