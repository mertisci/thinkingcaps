import AppKit

public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onCompleted: () -> Void
    private var pollTimer: Timer?
    private var currentScreen: OnboardingScreen
    private let statusLabel = NSTextField(labelWithString: "Status: waiting for permission…")

    public init(initialScreen: OnboardingScreen, onCompleted: @escaping () -> Void) {
        self.onCompleted = onCompleted
        self.currentScreen = initialScreen
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ThinkingCaps Setup"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        showScreen(initialScreen)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func showScreen(_ screen: OnboardingScreen) {
        currentScreen = screen
        pollTimer?.invalidate()
        pollTimer = nil
        switch screen {
        case .permission:
            window?.contentView = makePermissionView()
            startPollingForGrant()
        case .success:
            window?.contentView = makeSuccessView()
        }
    }

    // MARK: - Permission screen

    private func makePermissionView() -> NSView {
        let icon = makeIconView()

        let title = NSTextField(labelWithString: "Welcome to ThinkingCaps")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString:
            "ThinkingCaps blinks your keyboard's Caps Lock light while Claude Code is thinking. "
            + "To control the light, macOS requires the Input Monitoring permission.\n\n"
            + "Click Grant Permission, then enable ThinkingCaps in the System Settings list that opens. "
            + "macOS may ask to quit and reopen the app — that's expected, setup continues automatically."
        )
        body.alignment = .center
        body.preferredMaxLayoutWidth = 400

        statusLabel.stringValue = "Status: waiting for permission…"
        statusLabel.textColor = .secondaryLabelColor

        let grantButton = NSButton(title: "Grant Permission", target: self, action: #selector(grantTapped))
        grantButton.keyEquivalent = "\r"

        let settingsButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSettingsTapped))

        return makeStack([icon, title, body, statusLabel, grantButton, settingsButton])
    }

    @objc private func grantTapped() {
        InputMonitoringPermission.request()
        openInputMonitoringSettings()
    }

    @objc private func openSettingsTapped() {
        openInputMonitoringSettings()
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPollingForGrant() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if InputMonitoringPermission.isGranted() {
                self.showScreen(.success)
            }
        }
    }

    // MARK: - Success screen

    private func makeSuccessView() -> NSView {
        let icon = makeIconView()

        let title = NSTextField(labelWithString: "You're all set!")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString:
            "The Caps Lock light will blink while Claude Code is thinking, and stop when it's done.\n\n"
            + "Left-click the menu bar icon to turn ThinkingCaps on or off.\n"
            + "Right-click it for Launch at Login and Quit.\n\n"
            + "Claude Code integration was set up automatically."
        )
        body.alignment = .center
        body.preferredMaxLayoutWidth = 400

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneButton.keyEquivalent = "\r"

        return makeStack([icon, title, body, doneButton])
    }

    @objc private func doneTapped() {
        onCompleted()
        close()
    }

    // MARK: - Shared

    private func makeIconView() -> NSImageView {
        let imageView = NSImageView()
        if let image = NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: "ThinkingCaps") {
            image.isTemplate = true
            imageView.image = image
            imageView.symbolConfiguration = .init(pointSize: 44, weight: .regular)
        }
        return imageView
    }

    private func makeStack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 36, bottom: 28, right: 36)
        return stack
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        if currentScreen == .success {
            onCompleted()
        }
    }
}
