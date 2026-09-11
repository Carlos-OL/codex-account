import Foundation

struct MenuProfileItem: Equatable, Sendable {
    let profile: CodexAccountProfile
    let isEnabled: Bool
}

struct MenuState: Equatable, Sendable {
    var profiles: [CodexAccountProfile] = []
    var isSwitching = false
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
        orderedProfiles.map { MenuProfileItem(profile: $0, isEnabled: !isSwitching && !$0.active) }
    }

    var controlsEnabled: Bool {
        !isSwitching
    }

    mutating func beginSwitch() -> Bool {
        guard !isSwitching else {
            return false
        }

        isSwitching = true
        message = "Switching..."
        return true
    }

    mutating func finishSwitch(with profiles: [CodexAccountProfile]) {
        self.profiles = profiles
        isSwitching = false
        message = nil
    }

    mutating func finishWithError(_ error: Error) {
        isSwitching = false
        message = Self.redactedMessage(for: error)
    }

    static func redactedMessage(for error: Error) -> String {
        if let clientError = error as? CLIClientError {
            return clientError.localizedDescription
        }

        return "codex-account failed. Check the CLI and try again."
    }
}
