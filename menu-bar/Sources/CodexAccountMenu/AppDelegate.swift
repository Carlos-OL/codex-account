#if os(macOS)
import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let client = CLIClient()
    private var state = MenuState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.title = "Codex"
        }

        menu.delegate = self
        statusItem.menu = menu
        reloadProfiles()
    }

    func menuWillOpen(_ menu: NSMenu) {
        reloadProfiles()
    }

    private func reloadProfiles() {
        guard state.controlsEnabled else {
            renderMenu()
            return
        }

        do {
            state.profiles = try client.listProfiles()
            state.message = state.profiles.isEmpty ? "No profiles saved" : nil
        } catch {
            state.message = MenuState.redactedMessage(for: error)
        }

        renderMenu()
    }

    private func renderMenu() {
        menu.removeAllItems()

        if let message = state.message {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        for item in state.profileItems {
            let menuItem = NSMenuItem(title: title(for: item.profile), action: #selector(selectProfile(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.profile.name
            menuItem.state = item.profile.active ? .on : .off
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }

        if !state.profiles.isEmpty {
            menu.addItem(.separator())
        }

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshProfiles(_:)), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = state.controlsEnabled
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func title(for profile: CodexAccountProfile) -> String {
        if let usage = profile.usage, !usage.isEmpty {
            return "\(profile.name)  \(profile.email)  \(usage)"
        }

        return "\(profile.name)  \(profile.email)"
    }

    @objc private func refreshProfiles(_ sender: NSMenuItem) {
        reloadProfiles()
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, state.beginSwitch() else {
            return
        }

        renderMenu()

        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let result = Result {
                try client.useProfile(named: name)
                return try client.listProfiles()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                switch result {
                case let .success(profiles):
                    state.finishSwitch(with: profiles)
                case let .failure(error):
                    state.finishWithError(error)
                    reloadProfiles()
                    return
                }

                renderMenu()
            }
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
#endif
