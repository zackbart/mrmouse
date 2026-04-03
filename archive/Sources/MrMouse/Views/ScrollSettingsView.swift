import SwiftUI
import Config

struct ScrollSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var smartShiftEnabled: Bool = true
    @State private var smartShiftThreshold: Double = 30
    @State private var hiResScrollEnabled: Bool = true
    @State private var scrollInverted: Bool = false
    @State private var thumbWheelInverted: Bool = false

    private var deviceKey: String? {
        guard let dev = appState.selectedDevice else { return nil }
        return dev.hidppDevice.info.serialNumber ?? dev.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Smart Shift", isOn: $smartShiftEnabled)
                    .font(.subheadline)
                    .onChange(of: smartShiftEnabled) { _ in commit() }

                if smartShiftEnabled {
                    HStack {
                        Text("Threshold")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $smartShiftThreshold, in: 1...255, step: 1)
                            .onChange(of: smartShiftThreshold) { _ in commit() }
                        Text("\(Int(smartShiftThreshold))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                    }
                }
            }

            Divider()

            Toggle("High-Resolution Scrolling", isOn: $hiResScrollEnabled)
                .font(.subheadline)
                .onChange(of: hiResScrollEnabled) { _ in commit() }

            Divider()

            Toggle("Reverse Scroll Direction", isOn: $scrollInverted)
                .font(.subheadline)
                .onChange(of: scrollInverted) { _ in commit() }

            Toggle("Reverse Thumb Wheel", isOn: $thumbWheelInverted)
                .font(.subheadline)
                .onChange(of: thumbWheelInverted) { _ in commit() }
        }
        .onAppear { loadFromConfig() }
        .onChange(of: appState.selectedDeviceID) { _ in loadFromConfig() }
    }

    private func loadFromConfig() {
        guard let key = deviceKey else { return }
        let dev = appState.configManager.deviceConfig(for: key)
        smartShiftEnabled = dev.smartShiftEnabled
        smartShiftThreshold = Double(dev.smartShiftThreshold)
        hiResScrollEnabled = dev.hiResScrollEnabled
        scrollInverted = dev.scrollInverted
        thumbWheelInverted = dev.thumbWheelInverted
    }

    private func commit() {
        guard let key = deviceKey else { return }
        let enabled = smartShiftEnabled
        let threshold = Int(smartShiftThreshold)
        try? appState.configManager.update { config in
            var dev = config.devices[key] ?? DeviceConfig()
            dev.smartShiftEnabled = enabled
            dev.smartShiftThreshold = threshold
            dev.hiResScrollEnabled = hiResScrollEnabled
            dev.scrollInverted = scrollInverted
            dev.thumbWheelInverted = thumbWheelInverted
            config.devices[key] = dev
        }
        appState.setSmartShift(enabled: enabled, threshold: threshold)
    }
}
