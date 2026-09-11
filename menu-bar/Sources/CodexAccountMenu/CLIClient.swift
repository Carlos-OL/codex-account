import Foundation

struct CodexAccountProfile: Decodable, Equatable, Sendable {
    let name: String
    let email: String
    let active: Bool
    let usage: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case email
        case active
        case usage
    }

    init(name: String, email: String, active: Bool, usage: String? = nil) {
        self.name = name
        self.email = email
        self.active = active
        self.usage = usage
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

    var errorDescription: String? {
        switch self {
        case .invalidProfileName:
            return "Invalid profile name."
        case let .commandFailed(message):
            return message
        case .invalidResponse:
            return "codex-account returned an invalid profile list."
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

    func listProfiles() throws -> [CodexAccountProfile] {
        let result: ProcessResult
        do {
            result = try runner.run(ProcessCommand(executableURL: executableURL, arguments: ["list", "--json"]))
        } catch {
            throw CLIClientError.commandFailed(redactedLaunchFailureMessage())
        }

        guard result.exitCode == 0 else {
            throw CLIClientError.commandFailed(redactedFailureMessage(for: result.exitCode))
        }

        do {
            return try decoder.decode([CodexAccountProfile].self, from: result.standardOutput)
        } catch {
            throw CLIClientError.invalidResponse
        }
    }

    func useProfile(named name: String) throws {
        guard Self.isValidProfileName(name) else {
            throw CLIClientError.invalidProfileName
        }

        let result: ProcessResult
        do {
            result = try runner.run(ProcessCommand(executableURL: executableURL, arguments: ["use", name]))
        } catch {
            throw CLIClientError.commandFailed(redactedLaunchFailureMessage())
        }

        guard result.exitCode == 0 else {
            throw CLIClientError.commandFailed(redactedFailureMessage(for: result.exitCode))
        }
    }

    static func isValidProfileName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) == name.startIndex..<name.endIndex
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
        isExecutableFile: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> URL {
        if let configured = environment["CODEX_ACCOUNT_EXECUTABLE"], configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured)
        }

        let executablePaths = [
            "/opt/homebrew/bin/codex-account",
            "/usr/local/bin/codex-account",
        ]

        return URL(fileURLWithPath: executablePaths.first(where: isExecutableFile) ?? "/usr/local/bin/codex-account")
    }
}
