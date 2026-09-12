import Foundation

extension CodexAccountProfile {
    /// Builds the compact, display-safe title shown for a profile in the menu.
    ///
    /// - Returns: A title containing the name, email, and available five-hour and weekly labels.
    /// - Called by: `AppDelegate.renderMenu()`.
    var menuTitle: String {
        let limits: [String] = [fiveHourUsage, usage]
            .compactMap { (value: String?) -> String? in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }

        if !limits.isEmpty {
            return "\(name)  \(email)  \(limits.joined(separator: " · "))"
        }

        return "\(name)  \(email)"
    }
}

struct MenuProfileItem: Equatable, Sendable {
    let profile: CodexAccountProfile
    let isEnabled: Bool
}

struct MenuState: Equatable, Sendable {
    var profiles: [CodexAccountProfile] = []
    var isBusy = false
    var message: String?

    var orderedProfiles: [CodexAccountProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.active != rhs.active {
                return lhs.active && !rhs.active
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var profileItems: [MenuProfileItem] {
        orderedProfiles.map { MenuProfileItem(profile: $0, isEnabled: !isBusy && !$0.active) }
    }

    var controlsEnabled: Bool {
        !isBusy
    }

    /// Starts one mutually exclusive menu operation.
    ///
    /// - Parameter message: The progress text displayed while the operation runs.
    /// - Returns: `true` when the operation started, or `false` when another is active.
    /// - Called by: `AppDelegate` before invoking a CLI mutation.
    mutating func beginOperation(message: String) -> Bool {
        guard !isBusy else {
            return false
        }

        isBusy = true
        self.message = message
        return true
    }

    /// Completes a menu operation and stores its refreshed profiles and status.
    ///
    /// - Parameters:
    ///   - profiles: The refreshed saved profiles.
    ///   - message: The completion message displayed in the next menu opening.
    /// - Called by: `AppDelegate.runOperation(message:successMessage:operation:)`.
    mutating func finishOperation(with profiles: [CodexAccountProfile], message: String?) {
        self.profiles = profiles
        isBusy = false
        self.message = message
    }

    /// Completes a failed operation with a redacted user-facing message.
    ///
    /// - Parameter error: The CLI or application error to report safely.
    /// - Called by: `AppDelegate.runOperation(message:successMessage:operation:)`.
    /// - Calls: `redactedMessage(for:)`.
    mutating func finishWithError(_ error: Error) {
        isBusy = false
        message = Self.redactedMessage(for: error)
    }

    static func redactedMessage(for error: Error) -> String {
        if let clientError = error as? CLIClientError {
            return clientError.localizedDescription
        }

        return "codex-account failed. Check the CLI and try again."
    }
}
