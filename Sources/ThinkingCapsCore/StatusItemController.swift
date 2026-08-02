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
    private let blinkSpeedMenu = NSMenu()
    private let blinkSpeedMenuItem = NSMenuItem()

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

        blinkSpeedMenuItem.title = "Blink Speed"
        rightClickMenu.addItem(blinkSpeedMenuItem)
        for speed in BlinkSpeed.allCases {
            let item = NSMenuItem(title: speed.displayName, action: #selector(selectBlinkSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            item.state = blinkSettings.blinkSpeed == speed ? .on : .off
            blinkSpeedMenu.addItem(item)
        }
        rightClickMenu.setSubmenu(blinkSpeedMenu, for: blinkSpeedMenuItem)

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

    @objc private func selectBlinkSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let speed = BlinkSpeed(rawValue: raw) else { return }
        blinkSettings.setBlinkSpeed(speed)
        for item in blinkSpeedMenu.items {
            item.state = (item.representedObject as? String) == speed.rawValue ? .on : .off
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    public func setIconBlinkFrame(visible: Bool) {
        if visible {
            updateIcon()
        } else {
            statusItem.button?.image = Self.image(for: false)
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
