import AppKit

public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let socketServer: HookSocketServer
    private let launchAtLogin: LaunchAtLoginControlling
    private var isOn = true

    private let rightClickMenu = NSMenu()
    private let launchAtLoginMenuItem = NSMenuItem()

    public init(socketServer: HookSocketServer, launchAtLogin: LaunchAtLoginControlling) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.socketServer = socketServer
        self.launchAtLogin = launchAtLogin
        super.init()

        configureButton()
        configureMenu()
        updateIcon()
        socketServer.setEnabled(isOn)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.image(for: isOn)
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        launchAtLoginMenuItem.title = "Launch at Login"
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginMenuItem.state = launchAtLogin.isEnabled ? .on : .off
        rightClickMenu.addItem(launchAtLoginMenuItem)

        let quitItem = NSMenuItem(title: "Quit ThinkingCaps", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        rightClickMenu.addItem(quitItem)
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            isOn.toggle()
            socketServer.setEnabled(isOn)
            updateIcon()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !launchAtLogin.isEnabled
        launchAtLogin.setEnabled(newValue)
        launchAtLoginMenuItem.state = newValue ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateIcon() {
        statusItem.button?.image = Self.image(for: isOn)
    }

    private static func image(for isOn: Bool) -> NSImage? {
        let symbolName = isOn ? "capslock.fill" : "capslock"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isOn ? "ThinkingCaps On" : "ThinkingCaps Off")
        image?.isTemplate = true
        return image
    }
}
