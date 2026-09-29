//
//  AccountLastLoginTests.swift
//  ttaccessibleTests
//
//  The server reports an account that never logged in as the epoch, in its
//  own time zone: "1970/01/01 07:00" east of Greenwich, "1969/12/31 17:00"
//  west of it. VoiceOver read that out as a real date.
//

import XCTest
@testable import ttaccessible

final class AccountLastLoginTests: XCTestCase {

    private var never: String { L10n.text("accounts.lastLogin.never") }

    func testEpochEastOfGreenwichIsNever() {
        XCTAssertEqual(UserAccountsViewController.lastLoginDisplay("1970/01/01 07:00"), never)
    }

    func testEpochWestOfGreenwichIsNever() {
        XCTAssertEqual(UserAccountsViewController.lastLoginDisplay("1969/12/31 17:00"), never)
    }

    func testEmptyIsNever() {
        XCTAssertEqual(UserAccountsViewController.lastLoginDisplay(""), never)
    }

    func testRealDateIsKept() {
        XCTAssertEqual(UserAccountsViewController.lastLoginDisplay("2026/09/28 21:14"), "2026/09/28 21:14")
    }
}
