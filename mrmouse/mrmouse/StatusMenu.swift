import SwiftUI

/// Root view rendered inside the MenuBarExtra window.
/// Fixed ~320 pt wide; content scrolls if it overflows.
struct StatusMenu: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Device status ─────────────────────────────────────────
                DeviceStatusView()
                    .environmentObject(appState)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                // ── DPI ───────────────────────────────────────────────────
                SectionContainer(title: "DPI") {
                    DPISettingsView()
                        .environmentObject(appState)
                }

                Divider()

                // ── Scrolling ─────────────────────────────────────────────
                SectionContainer(title: "Scrolling") {
                    ScrollSettingsView()
                        .environmentObject(appState)
                }

                Divider()

                // ── Buttons ───────────────────────────────────────────────
                SectionContainer(title: "Buttons") {
                    ButtonMappingView()
                        .environmentObject(appState)
                }

                Divider()

                // ── Profiles ──────────────────────────────────────────────
                SectionContainer(title: "Profiles") {
                    ProfilesView()
                        .environmentObject(appState)
                }

                Divider()

                // ── Footer ────────────────────────────────────────────────
                HStack {
                    Spacer()
                    Button("Quit MrMouse") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
        .frame(width: 320)
    }
}

// MARK: - Section container

private struct SectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            content()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    StatusMenu()
        .environmentObject(AppState())
}
#endif
