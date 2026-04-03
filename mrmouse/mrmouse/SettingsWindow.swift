import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GesturesTab()
                .environmentObject(appState)
                .tabItem { Label("Gestures", systemImage: "hand.draw") }

            ButtonsTab()
                .environmentObject(appState)
                .tabItem { Label("Buttons", systemImage: "computermouse") }
        }
        .frame(minWidth: 420, minHeight: 380)
        .padding()
    }
}

// MARK: - Gestures Tab

private struct GesturesTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Gesture Button (thumb)") {
                Text("Hold and move mouse to swipe. Tap or swipe to trigger.")
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
                Text("App Exposé").tag(SystemAction.appExpose)
                Text("Show Desktop").tag(SystemAction.showDesktop)
                Text("Launchpad").tag(SystemAction.launchpad)
                Divider()
                Text("Desktop Left").tag(SystemAction.switchDesktopLeft)
                Text("Desktop Right").tag(SystemAction.switchDesktopRight)
                Divider()
                Text("Spotlight").tag(SystemAction.spotlight)
                Text("Screenshot").tag(SystemAction.screenshot)
                Text("Lock Screen").tag(SystemAction.lockScreen)
                Divider()
                Text("Volume Up").tag(SystemAction.volumeUp)
                Text("Volume Down").tag(SystemAction.volumeDown)
                Text("Mute").tag(SystemAction.mute)
                Text("Play/Pause").tag(SystemAction.playPause)
                Text("Next Track").tag(SystemAction.nextTrack)
                Text("Previous Track").tag(SystemAction.prevTrack)
            }
            .labelsHidden()
            .frame(width: 180)
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

#if DEBUG
#Preview {
    SettingsWindow()
        .environmentObject(AppState())
}
#endif
