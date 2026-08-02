import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var socketServer: HookSocketServer?
    private var onboardingController: OnboardingWindowController?
    private var blinker: Blinker?
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let appSupportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThinkingCaps")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let socketPath = appSupportDir.appendingPathComponent("ctl.sock").path

        let ledDevice = IOKitCapsLockLEDDevice()
        let iconBlinkOutput = MenuBarIconBlinkOutput()
        let blinkSettings = BlinkSettings(led: ledDevice, icon: iconBlinkOutput)
        let blinker = Blinker(devices: [blinkSettings.ledOutput, blinkSettings.iconOutput], interval: blinkSettings.blinkSpeed.interval)
        self.blinker = blinker
        blinkSettings.applyInterval = { [weak blinker] interval in
            blinker?.setInterval(interval)
        }
        let server = HookSocketServer(socketPath: socketPath, blinker: blinker)
        self.socketServer = server
        do {
            try server.start()
        } catch {
            NSLog("ThinkingCaps: failed to start hook socket server: \(error)")
        }

        let launchAtLogin = LaunchAtLogin()
        if !UserDefaults.standard.bool(forKey: "hasRunBefore") {
            launchAtLogin.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "hasRunBefore")
        }

        statusItemController = StatusItemController(socketServer: server, launchAtLogin: launchAtLogin, blinkSettings: blinkSettings)
        iconBlinkOutput.setIconVisible = { [weak self] visible in
            self?.statusItemController?.setIconBlinkFrame(visible: visible)
        }

        installClaudeHookIfNeeded()

        let initialScreen = OnboardingFlow.initialScreen(
            permissionGranted: InputMonitoringPermission.isGranted(),
            hasCompletedOnboarding: UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
        )
        if let initialScreen {
            presentOnboarding(initialScreen)
        }
    }

    private func presentOnboarding(_ screen: OnboardingScreen) {
        let controller = OnboardingWindowController(initialScreen: screen) {
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        }
        onboardingController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func installClaudeHookIfNeeded() {
        let settingsURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let notifierPath = Bundle.main.bundlePath + "/Contents/MacOS/hook-notify"
        let installer = ClaudeHookInstaller(settingsURL: settingsURL)
        do {
            try installer.install(notifierPath: notifierPath)
        } catch {
            NSLog("ThinkingCaps: failed to install Claude Code hooks: \(error)")
        }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        blinker?.stop()
        socketServer?.stop()
        return .terminateNow
    }
}
