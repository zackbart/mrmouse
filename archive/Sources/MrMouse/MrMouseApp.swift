import SwiftUI
import AppKit

@main
struct MrMouseApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        MenuBarExtra("MrMouse", systemImage: "computermouse.fill") {
            Button("Open Settings...") {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            if appState.devices.isEmpty {
                Text("No devices connected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.devices) { device in
                    let isSel = device.id == (appState.selectedDeviceID ?? appState.devices.first?.id)
                    Button {
                        appState.selectedDeviceID = device.id
                    } label: {
                        HStack {
                            if isSel { Image(systemName: "checkmark") }
                            Text("\(device.name) (\(device.transport.rawValue))")
                            if let battery = device.batteryLevel {
                                Text("\(battery)%")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Quit MrMouse") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Window("MrMouse Settings", id: "settings") {
            SettingsWindow()
                .environmentObject(appState)
        }
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
    }
}
