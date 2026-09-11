import Foundation
import XCTest
@testable import CodexAccountMenu

final class MenuModelTests: XCTestCase {
func testOrdersActiveProfileFirstThenByName() {
    let state = MenuState(profiles: [
        CodexAccountProfile(name: "zeta", email: "z@example.com", active: false),
        CodexAccountProfile(name: "active", email: "a@example.com", active: true),
        CodexAccountProfile(name: "alpha", email: "b@example.com", active: false),
    ])

    XCTAssertEqual(state.orderedProfiles.map(\.name), ["active", "alpha", "zeta"])
}

func testRendersInactiveProfilesSelectableAndActiveProfileCheckedOnly() {
    let state = MenuState(profiles: [
        CodexAccountProfile(name: "active", email: "a@example.com", active: true),
        CodexAccountProfile(name: "work", email: "w@example.com", active: false),
    ])

    XCTAssertEqual(state.profileItems, [
        MenuProfileItem(profile: CodexAccountProfile(name: "active", email: "a@example.com", active: true), isEnabled: false),
        MenuProfileItem(profile: CodexAccountProfile(name: "work", email: "w@example.com", active: false), isEnabled: true),
    ])
}

func testDisablesConcurrentSwitches() {
    var state = MenuState()

    XCTAssertTrue(state.beginSwitch())
    XCTAssertFalse(state.beginSwitch())
    XCTAssertFalse(state.controlsEnabled)
    XCTAssertTrue(state.profileItems.isEmpty)
}

func testMapsErrorsToRedactedMessages() {
    var state = MenuState(isSwitching: true)

    state.finishWithError(CLIClientError.commandFailed("codex-account failed with exit code 1. Check the CLI and try again."))

    XCTAssertFalse(state.isSwitching)
    XCTAssertEqual(state.message, "codex-account failed with exit code 1. Check the CLI and try again.")
}
}
