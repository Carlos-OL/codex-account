import Foundation
import XCTest
@testable import CodexAccountMenu

final class MenuModelTests: XCTestCase {
func testMenuTitleShowsFiveHourAndWeeklyLimits() {
    let profile = CodexAccountProfile(
        name: "work",
        email: "work@example.com",
        active: true,
        usage: "75% wk",
        fiveHourUsage: "40% 5h"
    )

    XCTAssertEqual(profile.menuTitle, "work  work@example.com  40% 5h · 75% wk")
}

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

    XCTAssertTrue(state.beginOperation(message: "Switching…"))
    XCTAssertFalse(state.beginOperation(message: "Saving…"))
    XCTAssertFalse(state.controlsEnabled)
    XCTAssertTrue(state.profileItems.isEmpty)
    XCTAssertEqual(state.message, "Switching…")
}

func testFinishesOperationWithRefreshedProfilesAndMessage() {
    var state = MenuState(isBusy: true, message: "Saving…")
    let profiles = [CodexAccountProfile(name: "work", email: "w@example.com", active: true)]

    state.finishOperation(with: profiles, message: "Saved 'work'.")

    XCTAssertFalse(state.isBusy)
    XCTAssertEqual(state.profiles, profiles)
    XCTAssertEqual(state.message, "Saved 'work'.")
}

func testMapsErrorsToRedactedMessages() {
    var state = MenuState(isBusy: true)

    state.finishWithError(CLIClientError.commandFailed("codex-account failed with exit code 1. Check the CLI and try again."))

    XCTAssertFalse(state.isBusy)
    XCTAssertEqual(state.message, "codex-account failed with exit code 1. Check the CLI and try again.")
}
}
