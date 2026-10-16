import AppKit
import SwiftUI
import ServiceManagement

@main
@MainActor
enum NotchIslandMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon, no app menu
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = NotchViewModel()
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    private var liveItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchWindowController(model: model)
        controller.show()
        notchController = controller

        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        notchController?.reposition()
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notch Island")

        let menu = NSMenu()
        menu.delegate = self

        let open = NSMenuItem(title: "Open Island", action: #selector(openIsland), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let live = NSMenuItem(title: "Show Live Activities Beside Notch", action: #selector(toggleLiveActivities), keyEquivalent: "")
        live.target = self
        menu.addItem(live)
        liveItem = live

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginItem = login

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Notch Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        liveItem?.state = model.liveActivitiesEnabled ? .on : .off
    }

    @objc private func openIsland() {
        notchController?.openSticky()
    }

    @objc private func toggleLiveActivities() {
        model.liveActivitiesEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login failed: \(error.localizedDescription)")
        }
    }
}
