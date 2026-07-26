//
//  CoalescedRequestTests.swift
//  ttaccessibleTests
//
//  Latest-value-wins semantics that keep key-repeat floods on the media panel
//  (broadcast gain, seek) from queuing a backlog of stale SDK updates that
//  keeps applying after the user releases the key.
//

import XCTest
@testable import ttaccessible

final class CoalescedRequestTests: XCTestCase {

    func testFirstSubmitSchedulesFollowUpsCoalesce() {
        let request = CoalescedRequest<Int>()
        XCTAssertTrue(request.submit(10), "first submit must schedule an apply pass")
        XCTAssertFalse(request.submit(20), "second submit must coalesce into the pending pass")
        XCTAssertFalse(request.submit(30))
        XCTAssertEqual(request.take(), 30, "the apply pass must see only the newest value")
    }

    func testTakeReschedulesNextSubmit() {
        let request = CoalescedRequest<Int>()
        XCTAssertTrue(request.submit(1))
        XCTAssertEqual(request.take(), 1)
        XCTAssertTrue(request.submit(2), "after take, the next submit schedules a new pass")
        XCTAssertEqual(request.take(), 2)
    }

    func testTakeWithoutSubmitReturnsNil() {
        let request = CoalescedRequest<Int>()
        XCTAssertNil(request.take())
        XCTAssertTrue(request.submit(5), "an empty take must not leave the box wedged")
    }
}
