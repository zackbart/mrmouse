import SwiftUI

struct DeviceStatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.devices.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("No devices connected")
                        .font(.headline)
                }
            } else {
                // Device picker (if multiple)
                if appState.devices.count > 1 {
                    Picker("Device", selection: Binding(
                        get: { appState.selectedDeviceID ?? appState.devices.first?.id ?? "" },
                        set: { appState.selectedDeviceID = $0 }
                    )) {
                        ForEach(appState.devices) { device in
                            Text("\(device.name) (\(device.transport.rawValue))")
                                .tag(device.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Selected device info
                if let device = appState.selectedDevice {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.headline)
                        Spacer()
                    }

                    HStack {
                        Image(systemName: "computermouse.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(device.name)
                            .font(.subheadline)
                        Text("via \(device.transport.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if let fw = device.firmwareVersion {
                            Text("(\(fw))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let level = device.batteryLevel {
                        HStack(spacing: 6) {
                            Image(systemName: batteryIconName(level: level, charging: device.batteryCharging))
                                .foregroundStyle(batteryColor(level: level))
                                .frame(width: 16)
                            Text("\(level)%")
                                .font(.subheadline)
                            if device.batteryCharging {
                                Text("Charging")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func batteryIconName(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case 88...:  return "battery.100"
        case 63...:  return "battery.75"
        case 38...:  return "battery.50"
        case 13...:  return "battery.25"
        default:     return "battery.0"
        }
    }

    private func batteryColor(level: Int) -> Color {
        switch level {
        case 21...: return .primary
        case 11...: return .yellow
        default:    return .red
        }
    }
}
