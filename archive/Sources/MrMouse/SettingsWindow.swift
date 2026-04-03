import SwiftUI
import Config

struct SettingsWindow: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gearshape") }

            GesturesTab()
                .environmentObject(appState)
                .tabItem { Label("Gestures", systemImage: "hand.draw") }

            ButtonsTab()
                .environmentObject(appState)
                .tabItem { Label("Buttons", systemImage: "computermouse") }

            ScrollingTab()
                .environmentObject(appState)
                .tabItem { Label("Scrolling", systemImage: "arrow.up.arrow.down") }

            ProfilesTab()
                .environmentObject(appState)
                .tabItem { Label("Profiles", systemImage: "person.2") }
        }
        .frame(minWidth: 480, minHeight: 400)
        .padding()
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Device") {
                DeviceStatusView()
                    .environmentObject(appState)
            }

            Section("DPI") {
                DPISettingsView()
                    .environmentObject(appState)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Gestures Tab

private struct GesturesTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Gesture Button") {
                Text("Hold the gesture button and move the mouse to trigger actions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                GestureRow(label: "Tap", icon: "hand.tap",
                           action: gestureBinding(\.tap))
                GestureRow(label: "Swipe Up", icon: "arrow.up",
                           action: gestureBinding(\.swipeUp))
                GestureRow(label: "Swipe Down", icon: "arrow.down",
                           action: gestureBinding(\.swipeDown))
                GestureRow(label: "Swipe Left", icon: "arrow.left",
                           action: gestureBinding(\.swipeLeft))
                GestureRow(label: "Swipe Right", icon: "arrow.right",
                           action: gestureBinding(\.swipeRight))
            }
        }
        .formStyle(.grouped)
    }

    private func gestureBinding(_ keyPath: WritableKeyPath<GestureActions, ButtonAction>) -> Binding<SystemAction> {
        Binding<SystemAction>(
            get: {
                if case .systemAction(let action) = appState.configManager.config.globalProfile.gestureActions[keyPath: keyPath] {
                    return action
                }
                return .missionControl
            },
            set: { newAction in
                try? appState.configManager.update { config in
                    config.globalProfile.gestureActions[keyPath: keyPath] = .systemAction(newAction)
                }
            }
        )
    }
}

private struct GestureRow: View {
    let label: String
    let icon: String
    @Binding var action: SystemAction

    var body: some View {
        LabeledContent {
            Picker("", selection: $action) {
                Text("Mission Control").tag(SystemAction.missionControl)
                Text("App Expose").tag(SystemAction.appExpose)
                Text("Switch Desktop Left").tag(SystemAction.switchDesktopLeft)
                Text("Switch Desktop Right").tag(SystemAction.switchDesktopRight)
                Text("Launchpad").tag(SystemAction.launchpad)
                Text("Show Desktop").tag(SystemAction.showDesktop)
                Divider()
                Text("Spotlight").tag(SystemAction.spotlight)
                Text("Screenshot").tag(SystemAction.screenshot)
                Text("Lock Screen").tag(SystemAction.lockScreen)
            }
            .labelsHidden()
            .frame(width: 200)
        } label: {
            Label(label, systemImage: icon)
        }
    }
}

// MARK: - Buttons Tab

private struct ButtonsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Button Mappings") {
                ButtonMappingView()
                    .environmentObject(appState)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scrolling Tab

private struct ScrollingTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Scroll Settings") {
                ScrollSettingsView()
                    .environmentObject(appState)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Profiles Tab

private struct ProfilesTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Per-App Profiles") {
                ProfilesView()
                    .environmentObject(appState)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    SettingsWindow()
        .environmentObject(AppState())
}
#endif
