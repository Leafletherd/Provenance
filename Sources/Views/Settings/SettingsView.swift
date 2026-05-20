import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("appearanceMode")      private var appearanceMode      = "system"
    @AppStorage("trackPasteSources")   private var trackPasteSources   = true
    @AppStorage("defaultExportFormat") private var defaultExportFormat = "pdf"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Appearance
            settingSection(
                title: "Appearance",
                description: "Sets the app window to light or dark mode, independent of macOS system preference."
            ) {
                Picker("", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 216)
            }

            Divider().padding(.top, Brand.spaceLG)

            // MARK: Export — PR-25: intent-first picker.
            settingSection(
                title: "Default Export Intent",
                description: "Pre-selects this intent when you open the Export tab. Can be changed per-export."
            ) {
                Picker("", selection: $defaultExportFormat) {
                    ForEach(ExportIntent.allCases, id: \.rawValue) { intent in
                        Text(intent.label).tag(intent.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 216)
            }

            Divider().padding(.top, Brand.spaceLG)

            // MARK: Privacy
            settingSection(
                title: "Privacy",
                description: "When enabled, Provenance silently monitors the clipboard and records where pasted text came from — source URL, app, or AI tool. No content is stored: only a 64-character preview and a SHA-256 hash."
            ) {
                Toggle("Track paste sources", isOn: $trackPasteSources)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider().padding(.top, Brand.spaceLG)

            // Done button
            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Brand.accent)
            }
            .padding(.top, Brand.spaceMD)
        }
        .padding(24)
        .frame(width: 400)
        .onChange(of: appearanceMode) { mode in
            applyAppearance(mode)
        }
        .onChange(of: trackPasteSources) { enabled in
            if enabled {
                PasteboardObserver.shared.start()
            } else {
                PasteboardObserver.shared.stop()
            }
        }
        .onAppear {
            applyAppearance(appearanceMode)
        }
    }

    // MARK: - Section layout

    @ViewBuilder
    private func settingSection(
        title: String,
        description: String,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Brand.spaceSM) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Brand.textPrimary)
            control()
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(Brand.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Appearance

    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}
