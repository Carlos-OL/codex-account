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
        result(stdout: #"[{"name":"work","email":"work@example.com","active":true},{"name":"personal","email":"me@example.com","active":false,"usage":"75% wk"}]"#)
    ])
    let client = CLIClient(executableURL: URL(fileURLWithPath: "/tmp/codex-account"), runner: runner)

    let profiles = try client.listProfiles()

    XCTAssertEqual(profiles, [
        CodexAccountProfile(name: "work", email: "work@example.com", active: true),
        CodexAccountProfile(name: "personal", email: "me@example.com", active: false, usage: "75% wk"),
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
        result()
    ])
    let client = CLIClient(executableURL: executable, runner: runner)

    try client.useProfile(named: "work.dev-1")

    XCTAssertEqual(runner.commands, [
        ProcessCommand(executableURL: executable, arguments: ["use", "work.dev-1"])
    ])
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
            isExecutableFile: { _ in false }
        ),
        URL(fileURLWithPath: "/custom/codex-account")
    )
}

func testExecutableLocatorUsesAppleSiliconHomebrewCandidate() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: [:],
            isExecutableFile: { $0 == "/opt/homebrew/bin/codex-account" || $0 == "/usr/local/bin/codex-account" }
        ),
        URL(fileURLWithPath: "/opt/homebrew/bin/codex-account")
    )
}

func testExecutableLocatorUsesIntelHomebrewCandidate() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: [:],
            isExecutableFile: { $0 == "/usr/local/bin/codex-account" }
        ),
        URL(fileURLWithPath: "/usr/local/bin/codex-account")
    )
}

func testExecutableLocatorFallsBackToIntelPath() {
    XCTAssertEqual(
        CLIExecutableLocator.defaultExecutableURL(
            environment: ["CODEX_ACCOUNT_EXECUTABLE": "codex-account"],
            isExecutableFile: { _ in false }
        ),
        URL(fileURLWithPath: "/usr/local/bin/codex-account")
    )
}
}
