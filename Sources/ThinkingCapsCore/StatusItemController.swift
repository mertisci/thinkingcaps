import AppKit

public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let socketServer: HookSocketServer
    private let launchAtLogin: LaunchAtLoginControlling
    private var isOn = true

    private let rightClickMenu = NSMenu()
    private let launchAtLoginMenuItem = NSMenuItem()
    private let blinkSettings: BlinkSettings
    private let blinkLEDMenuItem = NSMenuItem()
    private let blinkIconMenuItem = NSMenuItem()

    public init(socketServer: HookSocketServer, launchAtLogin: LaunchAtLoginControlling, blinkSettings: BlinkSettings) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.socketServer = socketServer
        self.launchAtLogin = launchAtLogin
        self.blinkSettings = blinkSettings
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
        blinkLEDMenuItem.title = "Blink Caps Lock Light"
        blinkLEDMenuItem.target = self
        blinkLEDMenuItem.action = #selector(toggleBlinkLED)
        blinkLEDMenuItem.state = blinkSettings.isLEDBlinkEnabled ? .on : .off
        rightClickMenu.addItem(blinkLEDMenuItem)

        blinkIconMenuItem.title = "Blink Menu Bar Icon"
        blinkIconMenuItem.target = self
        blinkIconMenuItem.action = #selector(toggleBlinkIcon)
        blinkIconMenuItem.state = blinkSettings.isIconBlinkEnabled ? .on : .off
        rightClickMenu.addItem(blinkIconMenuItem)

        rightClickMenu.addItem(.separator())

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

    @objc private func toggleBlinkLED() {
        blinkSettings.setLEDBlinkEnabled(!blinkSettings.isLEDBlinkEnabled)
        blinkLEDMenuItem.state = blinkSettings.isLEDBlinkEnabled ? .on : .off
    }

    @objc private func toggleBlinkIcon() {
        blinkSettings.setIconBlinkEnabled(!blinkSettings.isIconBlinkEnabled)
        blinkIconMenuItem.state = blinkSettings.isIconBlinkEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    public func setIconBlinkFrame(visible: Bool) {
        if visible {
            updateIcon()
        } else {
            statusItem.button?.image = nil
        }
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
