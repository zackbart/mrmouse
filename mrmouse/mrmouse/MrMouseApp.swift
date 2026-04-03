import SwiftUI
import AppKit

@main
struct MrMouseApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    static var logPath: String {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MrMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("mrmouse.log").path
    }

    init() {
        Self.setupFileLogging()
    }

    private static func setupFileLogging() {
        let fileManager = FileManager.default
        let path = logPath

        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            let separator = "\n=== RUN \(Date()) ===\n"
            handle.write(separator.data(using: .utf8)!)
            dup2(handle.fileDescriptor, STDERR_FILENO)
        }
        NSLog("[MrMouse] Logging to %@", path)
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
