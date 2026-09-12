import Foundation

struct CodexAccountProfile: Decodable, Equatable, Sendable {
    let name: String
    let email: String
    let active: Bool
    let usage: String?
    let fiveHourUsage: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case email
        case active
        case usage
        case fiveHourUsage = "five_hour_usage"
    }

    /// Creates a redacted profile for display in the account menu.
    ///
    /// - Parameters:
    ///   - name: The local profile name.
    ///   - email: The profile's display email.
    ///   - active: Whether this profile is currently active.
    ///   - usage: The optional weekly allowance label.
    ///   - fiveHourUsage: The optional five-hour allowance label.
    /// - Returns: A profile value containing display-safe fields only.
    /// - Called by: Menu state construction and tests.
    init(name: String, email: String, active: Bool, usage: String? = nil, fiveHourUsage: String? = nil) {
        self.name = name
        self.email = email
        self.active = active
        self.usage = usage
        self.fiveHourUsage = fiveHourUsage
    }

    init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedRawKeys = Set(CodingKeys.allCases.map(\.rawValue))
        let rawKeys = Set(rawContainer.allKeys.map(\.stringValue))

        guard rawKeys.isSubset(of: allowedRawKeys) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected profile field")
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        active = try container.decode(Bool.self, forKey: .active)
        usage = try container.decodeIfPresent(String.self, forKey: .usage)
        fiveHourUsage = try container.decodeIfPresent(String.self, forKey: .fiveHourUsage)
    }
}

private struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

struct ProcessCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
}

struct ProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol ProcessRunning: Sendable {
    func run(_ command: ProcessCommand) throws -> ProcessResult
}

struct FoundationProcessRunner: ProcessRunning {
    func run(_ command: ProcessCommand) throws -> ProcessResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout.fileHandleForReading.readDataToEndOfFile(),
            standardError: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

enum CLIClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidProfileName
    case commandFailed(String)
    case invalidResponse
    case switchVerificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidProfileName:
            return "Invalid profile name."
        case let .commandFailed(message):
            return message
        case .invalidResponse:
            return "codex-account returned an invalid profile list."
        case .switchVerificationFailed:
            return "Codex did not activate the selected account. Refresh and try again."
        }
    }
}

struct CLIClient<Runner: ProcessRunning>: Sendable {
    let executableURL: URL
    private let runner: Runner
    private let decoder: JSONDecoder

    init(executableURL: URL = URL(fileURLWithPath: "/usr/local/bin/codex-account"), runner: Runner) {
        self.executableURL = executableURL
        self.runner = runner
        self.decoder = JSONDecoder()
    }

    /// Loads the display-safe profile list from the CLI.
    ///
    /// - Returns: The saved profiles and their locally cached usage labels.
    /// - Called by: `AppDelegate` during launch, refreshes, and completed actions.
    /// - Calls: `runChecked(arguments:)` and `JSONDecoder.decode`.
    func listProfiles() throws -> [CodexAccountProfile] {
        let result = try runChecked(arguments: ["list", "--json"])

        do {
            return try decoder.decode([CodexAccountProfile].self, from: result.standardOutput)
        } catch {
            throw CLIClientError.invalidResponse
        }
    }

    /// Switches Codex to a saved profile.
    ///
    /// - Parameter name: The validated local profile name.
    /// - Called by: `AppDelegate.selectProfile(_:)`.
    /// - Calls: `runChecked(arguments:)` and `listProfiles()` to verify activation.
    func useProfile(named name: String) throws {
        guard Self.isValidProfileName(name) else {
            throw CLIClientError.invalidProfileName
        }

        _ = try runChecked(arguments: ["use", name])

        let profiles = try listProfiles()
        guard profiles.contains(where: { $0.name == name && $0.active }) else {
            throw CLIClientError.switchVerificationFailed
        }
    }

    /// Saves the current Codex sign-in under a local profile name.
    ///
    /// - Parameters:
    ///   - name: The validated profile name to create or update.
    ///   - overwrite: Whether an existing profile may be replaced.
    /// - Called by: `AppDelegate.saveCurrentProfile(_:)`.
    /// - Calls: `runChecked(arguments:)`.
    func saveProfile(named name: String, overwrite: Bool = false) throws {
        guard Self.isValidProfileName(name) else {
            throw CLIClientError.invalidProfileName
        }

        let arguments = overwrite ? ["--force", "save", name] : ["save", name]
        _ = try runChecked(arguments: arguments)
    }

    /// Signs out locally while preserving the active saved profile.
    ///
    /// - Called by: `AppDelegate.signOutToAddAccount(_:)`.
    /// - Calls: `runChecked(arguments:)`.
    func forgetActiveSignIn() throws {
        _ = try runChecked(arguments: ["forget"])
    }

    /// Removes an inactive saved profile and its local usage snapshot.
    ///
    /// - Parameter name: The validated inactive profile name to remove.
    /// - Called by: `AppDelegate.removeProfile(_:)`.
    /// - Calls: `runChecked(arguments:)`.
    func removeProfile(named name: String) throws {
        guard Self.isValidProfileName(name) else {
            throw CLIClientError.invalidProfileName
        }

        _ = try runChecked(arguments: ["remove", name])
    }

    static func isValidProfileName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) == name.startIndex..<name.endIndex
    }

    /// Executes one CLI command and converts process failures to redacted errors.
    ///
    /// - Parameter arguments: Individual command arguments passed without shell evaluation.
    /// - Returns: The successful process result.
    /// - Called by: All public CLI operations.
    /// - Calls: `ProcessRunning.run(_:)`.
    private func runChecked(arguments: [String]) throws -> ProcessResult {
        let result: ProcessResult
        do {
            result = try runner.run(ProcessCommand(executableURL: executableURL, arguments: arguments))
        } catch {
            throw CLIClientError.commandFailed(redactedLaunchFailureMessage())
        }

        guard result.exitCode == 0 else {
            throw CLIClientError.commandFailed(redactedFailureMessage(for: result.exitCode))
        }

        return result
    }

    private func redactedFailureMessage(for exitCode: Int32) -> String {
        "codex-account failed with exit code \(exitCode). Check the CLI and try again."
    }

    private func redactedLaunchFailureMessage() -> String {
        "Could not run codex-account. Check the configured executable path."
    }
}

extension CLIClient where Runner == FoundationProcessRunner {
    init(executableURL: URL = CLIExecutableLocator.defaultExecutableURL()) {
        self.init(executableURL: executableURL, runner: FoundationProcessRunner())
    }
}

enum CLIExecutableLocator {
    static func defaultExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutableFile: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL {
        if let configured = environment["CODEX_ACCOUNT_EXECUTABLE"], configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured)
        }

        let executablePaths = [
            homeDirectory.appendingPathComponent(".local/bin/codex-account").path,
            "/opt/homebrew/bin/codex-account",
            "/usr/local/bin/codex-account",
        ]

        return URL(fileURLWithPath: executablePaths.first(where: isExecutableFile) ?? "/usr/local/bin/codex-account")
    }
}
