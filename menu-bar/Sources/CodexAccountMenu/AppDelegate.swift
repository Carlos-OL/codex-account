#if os(macOS)
import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let client = CLIClient()
    private var state = MenuState()

    /// Creates the fixed-width account icon after AppKit finishes launching.
    ///
    /// - Parameter notification: The AppKit launch-completion notification.
    /// - Called by: AppKit when the menu helper finishes launching.
    /// - Calls: `reloadProfiles()` to populate the account menu.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "CodexAccountMenuStatusItem"
        item.isVisible = true
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "person.crop.circle.badge.checkmark", accessibilityDescription: "Codex accounts")
            button.imagePosition = .imageOnly
            button.toolTip = "Codex accounts"
        }

        menu.delegate = self
        item.menu = menu
        reloadProfiles(clearMessage: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        reloadProfiles()
    }

    /// Reloads profiles while optionally clearing a previous operation result.
    ///
    /// - Parameter clearMessage: Whether to discard any prior status message.
    /// - Called by: App launch, menu opening, and the Refresh action.
    /// - Calls: `CLIClient.listProfiles()` and `renderMenu()`.
    private func reloadProfiles(clearMessage: Bool = false) {
        guard state.controlsEnabled else {
            renderMenu()
            return
        }

        do {
            state.profiles = try client.listProfiles()
            if clearMessage {
                state.message = state.profiles.isEmpty ? "No profiles saved" : nil
            } else if state.profiles.isEmpty, state.message == nil {
                state.message = "No profiles saved"
            }
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
            let menuItem = NSMenuItem(title: item.profile.menuTitle, action: #selector(selectProfile(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.profile.name
            menuItem.state = item.profile.active ? .on : .off
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }

        if !state.profiles.isEmpty {
            menu.addItem(.separator())
        }

        let save = NSMenuItem(title: "Save Current Sign-In…", action: #selector(saveCurrentProfile(_:)), keyEquivalent: "s")
        save.target = self
        save.isEnabled = state.controlsEnabled
        menu.addItem(save)

        let signOut = NSMenuItem(title: "Sign Out to Add Account…", action: #selector(signOutToAddAccount(_:)), keyEquivalent: "")
        signOut.target = self
        signOut.isEnabled = state.controlsEnabled
        menu.addItem(signOut)

        let remove = NSMenuItem(title: "Remove Saved Account", action: nil, keyEquivalent: "")
        let removeMenu = NSMenu(title: "Remove Saved Account")
        for profile in state.orderedProfiles {
            let removeItem = NSMenuItem(title: "\(profile.name)  \(profile.email)", action: #selector(removeProfile(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = profile.name
            removeItem.isEnabled = state.controlsEnabled && !profile.active
            removeMenu.addItem(removeItem)
        }
        remove.submenu = removeMenu
        remove.isEnabled = state.controlsEnabled && state.profiles.contains { !$0.active }
        menu.addItem(remove)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshProfiles(_:)), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = state.controlsEnabled
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func refreshProfiles(_ sender: NSMenuItem) {
        reloadProfiles(clearMessage: true)
    }

    /// Switches to the profile represented by a clicked menu row.
    ///
    /// - Parameter sender: The profile menu item containing the validated name.
    /// - Called by: AppKit when a profile row is selected.
    /// - Calls: `runOperation(progressMessage:successMessage:operation:)`.
    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else {
            return
        }

        runOperation(progressMessage: "Switching…", successMessage: "Switched to '\(name)'.") { client in
            try client.useProfile(named: name)
        }
    }

    /// Prompts for a name and saves the current Codex sign-in.
    ///
    /// - Parameter sender: The menu item that initiated the action.
    /// - Called by: AppKit from “Save Current Sign-In…”.
    /// - Calls: `promptForProfileName()`, `confirm(...)`, and `runOperation(...)`.
    @objc private func saveCurrentProfile(_ sender: NSMenuItem) {
        guard let name = promptForProfileName() else {
            return
        }

        guard CLIClient<FoundationProcessRunner>.isValidProfileName(name) else {
            showAlert(
                title: "Invalid Profile Name",
                message: "Use 1–64 letters, numbers, dots, dashes, or underscores, beginning with a letter or number."
            )
            return
        }

        let overwrite = state.profiles.contains { $0.name == name }
        if overwrite, !confirm(
            title: "Overwrite '\(name)'?",
            message: "This replaces that saved account with the credentials from the current Codex sign-in.",
            actionTitle: "Overwrite"
        ) {
            return
        }

        runOperation(progressMessage: "Saving…", successMessage: "Saved the current sign-in as '\(name)'.") { client in
            try client.saveProfile(named: name, overwrite: overwrite)
        }
    }

    /// Signs out locally so Codex can present its account login screen.
    ///
    /// - Parameter sender: The menu item that initiated the action.
    /// - Called by: AppKit from “Sign Out to Add Account…”.
    /// - Calls: `confirm(...)` and `runOperation(...)`.
    @objc private func signOutToAddAccount(_ sender: NSMenuItem) {
        guard confirm(
            title: "Sign Out to Add an Account?",
            message: "Your current saved account and usage will be preserved. Codex will restart at its login screen.",
            actionTitle: "Sign Out"
        ) else {
            return
        }

        runOperation(
            progressMessage: "Signing out…",
            successMessage: "Signed out. Complete login in Codex, then choose Save Current Sign-In…"
        ) { client in
            try client.forgetActiveSignIn()
        }
    }

    /// Confirms and removes the inactive profile represented by a submenu item.
    ///
    /// - Parameter sender: The removal item containing the profile name.
    /// - Called by: AppKit from the Remove Saved Account submenu.
    /// - Calls: `confirm(...)` and `runOperation(...)`.
    @objc private func removeProfile(_ sender: NSMenuItem) {
        guard
            let name = sender.representedObject as? String,
            let profile = state.profiles.first(where: { $0.name == name }),
            !profile.active,
            confirm(
                title: "Remove '\(name)'?",
                message: "This deletes its saved local credentials and usage snapshot. It does not revoke the server session.",
                actionTitle: "Remove"
            )
        else {
            return
        }

        runOperation(progressMessage: "Removing…", successMessage: "Removed '\(name)'.") { client in
            try client.removeProfile(named: name)
        }
    }

    /// Runs one CLI mutation away from the main thread and refreshes the menu.
    ///
    /// - Parameters:
    ///   - progressMessage: Status displayed while the action is running.
    ///   - successMessage: Status displayed after the action succeeds.
    ///   - operation: The validated CLI operation to execute.
    /// - Called by: Profile switching, save, sign-out, and removal actions.
    /// - Calls: `MenuState.beginOperation(message:)` and `CLIClient.listProfiles()`.
    private func runOperation(
        progressMessage: String,
        successMessage: String,
        operation: @escaping @Sendable (CLIClient<FoundationProcessRunner>) throws -> Void
    ) {
        guard state.beginOperation(message: progressMessage) else {
            return
        }

        renderMenu()

        DispatchQueue.global(qos: .userInitiated).async { [client] in
            let result = Result {
                try operation(client)
                return try client.listProfiles()
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                switch result {
                case let .success(profiles):
                    state.finishOperation(with: profiles, message: successMessage)
                case let .failure(error):
                    state.finishWithError(error)
                }

                renderMenu()
            }
        }
    }

    /// Requests a profile name in a modal text field.
    ///
    /// - Returns: The trimmed name when Save is chosen, otherwise `nil`.
    /// - Called by: `saveCurrentProfile(_:)`.
    private func promptForProfileName() -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Example: personal or work"

        let alert = NSAlert()
        alert.messageText = "Save Current Sign-In"
        alert.informativeText = "Choose a short name for the account currently open in Codex."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Presents a confirmation before a credential-changing action.
    ///
    /// - Parameters:
    ///   - title: The confirmation heading.
    ///   - message: The action's local effect.
    ///   - actionTitle: The affirmative button title.
    /// - Returns: `true` only when the affirmative button is chosen.
    /// - Called by: Save overwrite, sign-out, and removal actions.
    private func confirm(title: String, message: String, actionTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Displays a non-sensitive validation or operation message.
    ///
    /// - Parameters:
    ///   - title: The alert heading.
    ///   - message: The display-safe explanation.
    /// - Called by: `saveCurrentProfile(_:)` for local validation failures.
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
#endif
