import SwiftUI
import AppKit
import Config

// MARK: - Model

struct AppProfileEntry: Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// Per-app profiles list. Add profiles from running apps; delete them.
/// Each entry is keyed by bundle ID and overrides button mappings.
struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingAppPicker = false
    @State private var selectedBundleID: String? = nil

    private var appProfiles: [AppProfileEntry] {
        appState.configManager.config.appProfiles.keys
            .sorted()
            .map { AppProfileEntry(bundleID: $0, name: appDisplayName($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if appProfiles.isEmpty {
                Text("No per-app profiles. Add one to override button mappings for a specific app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            } else {
                profileListRows
            }

            HStack(spacing: 10) {
                Button {
                    showingAppPicker = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let id = selectedBundleID {
                    Button(role: .destructive) {
                        deleteProfile(id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet { bundleID in
                addProfile(bundleID: bundleID)
                showingAppPicker = false
            } onCancel: {
                showingAppPicker = false
            }
        }
    }

    // MARK: - Profile list rows

    @ViewBuilder
    private var profileListRows: some View {
        let profiles: [AppProfileEntry] = appProfiles
        ForEach(profiles, id: \.id, content: profileRow(entry:))
    }

    @ViewBuilder
    private func profileRow(entry: AppProfileEntry) -> some View {
        Button {
            selectedBundleID = entry.bundleID
        } label: {
            HStack(spacing: 8) {
                appIcon(bundleID: entry.bundleID)
                    .frame(width: 20, height: 20)
                Text(entry.name)
                    .font(.subheadline)
                Spacer()
                if selectedBundleID == entry.bundleID {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider()
    }

    // MARK: - Mutations

    private func addProfile(bundleID: String) {
        try? appState.configManager.update { config in
            if config.appProfiles[bundleID] == nil {
                config.appProfiles[bundleID] = config.globalProfile
            }
        }
        selectedBundleID = bundleID
    }

    private func deleteProfile(_ bundleID: String) {
        try? appState.configManager.update { config in
            config.appProfiles.removeValue(forKey: bundleID)
        }
        if selectedBundleID == bundleID {
            selectedBundleID = nil
        }
    }

    // MARK: - Helpers

    private func appDisplayName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent ?? bundleID
    }

    private func appIcon(bundleID: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let nsImage = url.flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
        return Group {
            if let img = nsImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - App picker sheet

private struct RunningAppEntry: Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

private struct AppPickerSheet: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var runningApps: [RunningAppEntry] = []
    @State private var searchText: String = ""

    private var filtered: [RunningAppEntry] {
        guard !searchText.isEmpty else { return runningApps }
        let q = searchText.lowercased()
        return runningApps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select App")
                .font(.headline)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(filtered) { app in
                Button {
                    onSelect(app.bundleID)
                } label: {
                    HStack(spacing: 8) {
                        appIcon(bundleID: app.bundleID)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.subheadline)
                            Text(app.bundleID)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 240)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { loadRunningApps() }
    }

    private func loadRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .compactMap { app -> RunningAppEntry? in
                guard
                    app.activationPolicy == .regular,
                    let id = app.bundleIdentifier,
                    let name = app.localizedName
                else { return nil }
                return RunningAppEntry(bundleID: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    private func appIcon(bundleID: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let nsImage = url.flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
        return Group {
            if let img = nsImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ProfilesView()
        .environmentObject({
            let s = AppState()
            return s
        }())
        .padding()
        .frame(width: 288)
}
#endif
