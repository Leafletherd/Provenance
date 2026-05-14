import AppKit
import ObjectiveC.runtime

// MARK: - ConnectProjectFlow

/// Central coordinator for the "connect a project folder" interaction.
///
/// Both the sidebar + button and the Home view's "Connect Project…" button funnel
/// through here. The panel includes an accessory view that offers a one-click
/// escape hatch for users who don't yet have a folder on disk.
enum ConnectProjectFlow {

    /// Opens the connect-project NSOpenPanel with the "Create New Project Folder…"
    /// accessory view at the bottom.
    ///
    /// - Parameters:
    ///   - didRequestCreate: Fired when the user clicks "Create New Project Folder…".
    ///     The panel is already dismissed when this callback runs.
    ///   - onConnect: Fired when the user selects an existing folder normally.
    static func openPanel(
        didRequestCreate: @escaping () -> Void,
        onConnect: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Connect Project Folder"
        panel.message = "Choose the folder you want to track with Provenance."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.accessoryView = makeAccessoryView(panel: panel, onCreateTapped: didRequestCreate)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onConnect(url)
        }
    }

    // MARK: - Accessory view

    private static func makeAccessoryView(
        panel: NSOpenPanel,
        onCreateTapped: @escaping () -> Void
    ) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 36))

        // 0.5pt horizontal separator at the top of the accessory strip
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)

        // Left label
        let label = NSTextField(labelWithString: "Don\u{2019}t have a folder yet?")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        // Right button
        let button = NSButton(
            title: "Create New Project Folder\u{2026}",
            target: nil,
            action: nil
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        // Wire action — keep the handler alive via objc association on the button
        let handler = _ButtonHandler {
            panel.cancel(nil)
            DispatchQueue.main.async { onCreateTapped() }
        }
        button.target = handler
        button.action = #selector(_ButtonHandler.handleClick)
        objc_setAssociatedObject(
            button,
            &_AssociatedKeys.handlerKey,
            handler,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        NSLayoutConstraint.activate([
            // Separator pinned to top edge
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.topAnchor.constraint(equalTo: container.topAnchor),

            // Label 12pt from leading, vertically centred
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 2),

            // Button 12pt from trailing, vertically centred
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 2),
        ])

        return container
    }
}

// MARK: - Private helpers

private enum _AssociatedKeys {
    static var handlerKey: UInt8 = 0
}

private final class _ButtonHandler: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func handleClick() { action() }
}
