import SwiftUI
import Config

/// List of button mappings for the active profile.
/// Each row shows the button name and current action; tapping opens an action picker.
struct ButtonMappingView: View {
    @EnvironmentObject private var appState: AppState

    /// Index of the mapping being edited (nil = picker closed)
    @State private var editingIndex: Int? = nil

    private var profile: Profile {
        appState.configManager.profileForApp(appState.currentApp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(profile.buttonMappings.indices, id: \.self) { idx in
                let mapping = profile.buttonMappings[idx]

                Button {
                    editingIndex = idx
                } label: {
                    HStack {
                        Text(buttonName(for: mapping.controlID))
                            .font(.subheadline)
                        Spacer()
                        Text(actionLabel(mapping.action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if idx < profile.buttonMappings.count - 1 {
                    Divider()
                }
            }
        }
        .sheet(item: $editingIndex) { idx in
            ActionPickerView(
                buttonName: buttonName(for: profile.buttonMappings[idx].controlID),
                currentAction: profile.buttonMappings[idx].action
            ) { newAction in
                saveAction(newAction, at: idx)
                editingIndex = nil
            } onCancel: {
                editingIndex = nil
            }
        }
    }

    // MARK: - Helpers

    private func saveAction(_ action: ButtonAction, at index: Int) {
        let isGlobal = appState.currentApp == nil
        try? appState.configManager.update { config in
            if isGlobal {
                if index < config.globalProfile.buttonMappings.count {
                    var mapping = config.globalProfile.buttonMappings[index]
                    mapping.action = action
                    mapping.diverted = (action != .default && action != .disabled)
                    config.globalProfile.buttonMappings[index] = mapping
                }
            } else if let bundleID = appState.currentApp {
                var profile = config.appProfiles[bundleID] ?? config.globalProfile
                if index < profile.buttonMappings.count {
                    var mapping = profile.buttonMappings[index]
                    mapping.action = action
                    mapping.diverted = (action != .default && action != .disabled)
                    profile.buttonMappings[index] = mapping
                }
                config.appProfiles[bundleID] = profile
            }
        }
    }

    private func buttonName(for controlID: UInt16) -> String {
        switch controlID {
        case 0x0050: return "Left Click"
        case 0x0051: return "Right Click"
        case 0x0052: return "Middle Click"
        case 0x0053: return "Back"
        case 0x0056: return "Forward"
        case 0x00C3: return "Gesture Button"
        case 0x00C4: return "Smart Shift"
        default:     return "Button 0x\(String(controlID, radix: 16, uppercase: true))"
        }
    }

    private func actionLabel(_ action: ButtonAction) -> String {
        switch action {
        case .default:                          return "Default"
        case .disabled:                         return "Disabled"
        case .gestureButton:                    return "Gesture"
        case .keyboardShortcut(let combo):      return keyComboLabel(combo)
        case .systemAction(let action):         return systemActionLabel(action)
        case .openApp(let bundleID):            return appName(bundleID: bundleID)
        }
    }

    private func keyComboLabel(_ combo: KeyCombo) -> String {
        var parts: [String] = []
        if combo.modifiers.contains(.control) { parts.append("^") }
        if combo.modifiers.contains(.option)  { parts.append("⌥") }
        if combo.modifiers.contains(.shift)   { parts.append("⇧") }
        if combo.modifiers.contains(.command) { parts.append("⌘") }
        parts.append("Key(\(combo.keyCode))")
        return parts.joined()
    }

    private func systemActionLabel(_ action: SystemAction) -> String {
        switch action {
        case .missionControl:    return "Mission Control"
        case .appExpose:         return "App Exposé"
        case .switchDesktopLeft: return "Switch Desktop Left"
        case .switchDesktopRight:return "Switch Desktop Right"
        case .launchpad:         return "Launchpad"
        case .showDesktop:    return "Show Desktop"
        case .volumeUp:       return "Volume Up"
        case .volumeDown:     return "Volume Down"
        case .mute:           return "Mute"
        case .playPause:      return "Play/Pause"
        case .nextTrack:      return "Next Track"
        case .prevTrack:      return "Previous Track"
        case .screenshot:     return "Screenshot"
        case .spotlight:      return "Spotlight"
        case .lockScreen:     return "Lock Screen"
        }
    }

    private func appName(bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent ?? bundleID
    }
}

// MARK: - Int as Identifiable (for sheet(item:))

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Action picker sheet

private struct ActionPickerView: View {
    let buttonName: String
    let currentAction: ButtonAction
    let onSave: (ButtonAction) -> Void
    let onCancel: () -> Void

    @State private var selected: ActionKind = .default

    enum ActionKind: String, CaseIterable, Identifiable {
        case `default`     = "Default"
        case systemAction  = "System Action"
        case disabled      = "Disabled"
        case openApp       = "Open App"
        var id: String { rawValue }
    }

    @State private var selectedSystemAction: SystemAction = .missionControl

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign: \(buttonName)")
                .font(.headline)

            Picker("Action", selection: $selected) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if selected == .systemAction {
                Picker("System Action", selection: $selectedSystemAction) {
                    ForEach(SystemAction.allCases, id: \.self) { action in
                        Text(systemActionLabel(action)).tag(action)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSave(buildAction())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { syncFromCurrent() }
    }

    private func syncFromCurrent() {
        switch currentAction {
        case .default:               selected = .default
        case .disabled:              selected = .disabled
        case .openApp:               selected = .openApp
        case .systemAction(let a):   selected = .systemAction; selectedSystemAction = a
        case .keyboardShortcut, .gestureButton:
            selected = .default
        }
    }

    private func buildAction() -> ButtonAction {
        switch selected {
        case .default:       return .default
        case .disabled:      return .disabled
        case .systemAction:  return .systemAction(selectedSystemAction)
        case .openApp:       return .default  // full app picker out of scope here
        }
    }

    private func systemActionLabel(_ action: SystemAction) -> String {
        switch action {
        case .missionControl:    return "Mission Control"
        case .appExpose:         return "App Exposé"
        case .switchDesktopLeft: return "Switch Desktop Left"
        case .switchDesktopRight:return "Switch Desktop Right"
        case .launchpad:         return "Launchpad"
        case .showDesktop:    return "Show Desktop"
        case .volumeUp:       return "Volume Up"
        case .volumeDown:     return "Volume Down"
        case .mute:           return "Mute"
        case .playPause:      return "Play/Pause"
        case .nextTrack:      return "Next Track"
        case .prevTrack:      return "Previous Track"
        case .screenshot:     return "Screenshot"
        case .spotlight:      return "Spotlight"
        case .lockScreen:     return "Lock Screen"
        }
    }
}

extension SystemAction: CaseIterable {
    public static var allCases: [SystemAction] = [
        .missionControl, .appExpose, .switchDesktopLeft, .switchDesktopRight,
        .launchpad, .showDesktop,
        .volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .prevTrack,
        .screenshot, .spotlight, .lockScreen
    ]
}

// MARK: - Preview

#if DEBUG
#Preview {
    ButtonMappingView()
        .environmentObject(AppState())
        .padding()
        .frame(width: 288)
}
#endif
