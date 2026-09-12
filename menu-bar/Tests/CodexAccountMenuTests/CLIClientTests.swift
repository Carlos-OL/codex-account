import Foundation
import XCTest
@testable import CodexAccountMenu

private final class StubRunner: ProcessRunning, @unchecked Sendable {
    var results: [ProcessResult]
    private(set) var commands: [ProcessCommand] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(_ command: ProcessCommand) throws -> ProcessResult {
        commands.append(command)
        return results.removeFirst()
    }
}

private func result(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") -> ProcessResult {
    ProcessResult(
        exitCode: exitCode,
        standardOutput: Data(stdout.utf8),
        standardError: Data(stderr.utf8)
    )
}

final class CLIClientTests: XCTestCase {
func testDecodesValidRedactedProfileList() throws {
    let runner = StubRunner(results: [
        result(stdout: #"[{"name":"work","email":"work@example.com","active":true},{"name":"personal","email":"me@example.com","active":false,"usage":"75% wk","five_hour_usage":"40% 5h"}]"#)
    ])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    let profiles = try client.listProfiles()

    XCTAssertEqual(profiles, [
        CodexAccountProfile(name: "work", email: "work@example.com", active: true),
        CodexAccountProfile(name: "personal", email: "me@example.com", active: false, usage: "75% wk", fiveHourUsage: "40% 5h"),
    ])
}

func testRejectsUnexpectedProfileFields() throws {
    let runner = StubRunner(results: [
        result(stdout: #"[{"name":"work","email":"work@example.com","active":true,"account_id":"secret"}]"#)
    ])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    XCTAssertThrowsError(try client.listProfiles()) { error in
        XCTAssertEqual(error as? CLIClientError, .invalidResponse)
    }
}

func testRejectsMissingProfileFields() throws {
    let runner = StubRunner(results: [
        result(stdout: #"[{"name":"work","email":"work@example.com"}]"#)
    ])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    XCTAssertThrowsError(try client.listProfiles()) { error in
        XCTAssertEqual(error as? CLIClientError, .invalidResponse)
    }
}

func testListCommandUsesExecutableURLAndIndividualArguments() throws {
    let executable = URL(fileURLWithPath: "/opt/bin/codex-account")
    let runner = StubRunner(results: [
        result(stdout: #"[]"#)
    ])
    let client = CLIClient(executableURL: executable, runner: runner)

    _ = try client.listProfiles()

    XCTAssertEqual(runner.commands, [
        ProcessCommand(executableURL: executable, arguments: ["list", "--json"])
    ])
}

func testUseCommandRejectsInvalidProfileNameBeforeLaunch() throws {
    let runner = StubRunner(results: [])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    XCTAssertThrowsError(try client.useProfile(named: "work; rm token")) { error in
        XCTAssertEqual(error as? CLIClientError, .invalidProfileName)
    }
    XCTAssertTrue(runner.commands.isEmpty)
}

func testUseCommandPassesProfileAsSingleArgument() throws {
    let executable = URL(fileURLWithPath: "/opt/bin/codex-account")
    let runner = StubRunner(results: [
        result(),
        result(stdout: #"[{"name":"work.dev-1","email":"work@example.com","active":true}]"#),
    ])
    let client = CLIClient(executableURL: executable, runner: runner)

    try client.useProfile(named: "work.dev-1")

    XCTAssertEqual(runner.commands, [
        ProcessCommand(executableURL: executable, arguments: ["use", "work.dev-1"]),
        ProcessCommand(executableURL: executable, arguments: ["list", "--json"]),
    ])
}

func testUseCommandFailsWhenSelectedProfileIsNotActiveAfterSwitch() throws {
    let runner = StubRunner(results: [
        result(),
        result(stdout: #"[{"name":"work","email":"work@example.com","active":false},{"name":"other","email":"other@example.com","active":true}]"#),
    ])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    XCTAssertThrowsError(try client.useProfile(named: "work")) { error in
        XCTAssertEqual(error as? CLIClientError, .switchVerificationFailed)
    }
}

func testSaveCommandUsesForceOnlyAfterConfirmedOverwrite() throws {
    let executable = URL(fileURLWithPath: "/opt/bin/codex-account")
    let runner = StubRunner(results: [result(), result()])
    let client = CLIClient(executableURL: executable, runner: runner)

    try client.saveProfile(named: "new-account")
    try client.saveProfile(named: "existing", overwrite: true)

    XCTAssertEqual(runner.commands, [
        ProcessCommand(executableURL: executable, arguments: ["save", "new-account"]),
        ProcessCommand(executableURL: executable, arguments: ["--force", "save", "existing"]),
    ])
}

func testSaveCommandRejectsInvalidNameBeforeLaunch() throws {
    let runner = StubRunner(results: [])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    XCTAssertThrowsError(try client.saveProfile(named: "bad account")) { error in
        XCTAssertEqual(error as? CLIClientError, .invalidProfileName)
    }
    XCTAssertTrue(runner.commands.isEmpty)
}

func testForgetCommandUsesNoExtraArguments() throws {
    let executable = URL(fileURLWithPath: "/opt/bin/codex-account")
    let runner = StubRunner(results: [result()])
    let client = CLIClient(executableURL: executable, runner: runner)

    try client.forgetActiveSignIn()

    XCTAssertEqual(runner.commands, [
        ProcessCommand(executableURL: executable, arguments: ["forget"]),
    ])
}

func testRemoveCommandPassesValidatedNameWithoutForce() throws {
    let executable = URL(fileURLWithPath: "/opt/bin/codex-account")
    let runner = StubRunner(results: [result()])
    let client = CLIClient(executableURL: executable, runner: runner)

    try client.removeProfile(named: "old-account")

    XCTAssertEqual(runner.commands, [
        ProcessCommand(executableURL: executable, arguments: ["remove", "old-account"]),
    ])
}

func testRemoveCommandRejectsInvalidNameBeforeLaunch() throws {
    let runner = StubRunner(results: [])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    XCTAssertThrowsError(try client.removeProfile(named: "bad/account")) { error in
        XCTAssertEqual(error as? CLIClientError, .invalidProfileName)
    }
    XCTAssertTrue(runner.commands.isEmpty)
}

func testFailureOutputIsRedactedAndBounded() throws {
    let runner = StubRunner(results: [
        result(exitCode: 1, stdout: "refresh_token=rt-secret", stderr: "auth.json /Users/me/.codex")
    ])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    do {
        _ = try client.listProfiles()
        XCTFail("Expected command failure")
    } catch let error as CLIClientError {
        let message = error.localizedDescription
        XCTAssertLessThan(message.count, 120)
        XCTAssertFalse(message.contains("rt-secret"))
        XCTAssertFalse(message.contains("auth.json"))
        XCTAssertFalse(message.contains("/Users/me"))
    }
}

func testExecutableLocatorUsesConfiguredAbsolutePath() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: ["CODEX_ACCOUNT_EXECUTABLE": "/custom/codex-account"],
            homeDirectory: URL(fileURLWithPath: "/Users/example"),
            isExecutableFile: { _ in false }
        ),
        URL(fileURLWithPath: "/custom/codex-account")
    )
}

func testExecutableLocatorUsesUserLocalCandidateBeforeHomebrew() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/example"),
            isExecutableFile: {
                $0 == "/Users/example/.local/bin/codex-account" ||
                    $0 == "/opt/homebrew/bin/codex-account" ||
                    $0 == "/usr/local/bin/codex-account"
            }
        ),
        URL(fileURLWithPath: "/Users/example/.local/bin/codex-account")
    )
}

func testExecutableLocatorUsesAppleSiliconHomebrewCandidate() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/example"),
            isExecutableFile: { $0 == "/opt/homebrew/bin/codex-account" || $0 == "/usr/local/bin/codex-account" }
        ),
        URL(fileURLWithPath: "/opt/homebrew/bin/codex-account")
    )
}

func testExecutableLocatorUsesIntelHomebrewCandidate() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/example"),
            isExecutableFile: { $0 == "/usr/local/bin/codex-account" }
        ),
        URL(fileURLWithPath: "/usr/local/bin/codex-account")
    )
}

func testExecutableLocatorFallsBackToIntelPath() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: ["CODEX_ACCOUNT_EXECUTABLE": "codex-account"],
            homeDirectory: URL(fileURLWithPath: "/Users/example"),
            isExecutableFile: { _ in false }
        ),
        URL(fileURLWithPath: "/usr/local/bin/codex-account")
    )
}
}
