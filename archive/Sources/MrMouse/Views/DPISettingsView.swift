import SwiftUI
import Config

struct DPISettingsView: View {
    @EnvironmentObject private var appState: AppState

    private let presets: [Int] = [800, 1000, 1200, 1600, 2400, 4000]
    private let dpiRange: ClosedRange<Double> = 200...8000
    private let dpiStep: Double = 50

    @State private var sliderValue: Double = 1000

    private var currentDPI: Int {
        appState.selectedDevice?.currentDPI ?? 1000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sensitivity")
                    .font(.subheadline)
                Spacer()
                Text("\(Int(sliderValue)) DPI")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $sliderValue,
                in: dpiRange,
                step: dpiStep
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text("200").font(.caption2).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("8K").font(.caption2).foregroundStyle(.tertiary)
            }
            .onChange(of: sliderValue) { newValue in
                appState.setDPI(Int(newValue))
            }

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        sliderValue = Double(preset)
                        appState.setDPI(preset)
                    } label: {
                        Text(presetLabel(preset))
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Int(sliderValue) == preset ? .accentColor : nil)
                }
            }
        }
        .onAppear { sliderValue = Double(currentDPI) }
        .onChange(of: currentDPI) { newDPI in sliderValue = Double(newDPI) }
        .onChange(of: appState.selectedDeviceID) { _ in sliderValue = Double(currentDPI) }
    }

    private func presetLabel(_ dpi: Int) -> String {
        dpi >= 1000 ? "\(dpi / 1000)K" : "\(dpi)"
    }
}
