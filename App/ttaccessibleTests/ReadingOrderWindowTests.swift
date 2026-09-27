//
//  ReadingOrderWindowTests.swift
//  ttaccessibleTests
//
//  VoiceOver walks the connected window by its navigation order, which AppKit sorts on
//  screen position: the content pane's levels, level with the sidebar's labels, were read
//  between them. ReadingOrderWindow keeps AppKit's slots and puts the content back in
//  AXChildren order.
//

import XCTest
@testable import ttaccessible

final class ReadingOrderWindowTests: XCTestCase {

    private final class Element: CustomStringConvertible {
        let description: String
        init(_ name: String) { description = name }
    }

    func testTheContentFollowsItsChildrenOrderAndTheChromeKeepsItsPlace() {
        let close = Element("close"), toolbar = Element("toolbar")
        let server = Element("server"), status = Element("status"), tree = Element("tree")
        let output = Element("output"), input = Element("input"), chat = Element("chat")
        let content: [Element] = [server, status, tree, output, input, chat]

        // What AppKit hands over for two panes: row by row, left to right.
        let spatial: [Any] = [close, toolbar, server, output, status, input, tree, chat]
        let children: [Any] = content + [toolbar, close]

        let order = ReadingOrderWindow.readingOrder(
            spatial: spatial, children: children,
            isContent: { element in content.contains { $0 === (element as AnyObject) } }
        )
        XCTAssertEqual(order.map { "\($0)" },
                       ["close", "toolbar", "server", "status", "tree", "output", "input", "chat"])
    }

    func testAnElementTheChildrenDoNotListKeepsAppKitsOrderAfterTheOthers() {
        let a = Element("a"), b = Element("b"), stray = Element("stray")
        let order = ReadingOrderWindow.readingOrder(
            spatial: [stray, b, a], children: [a, b], isContent: { _ in true }
        )
        XCTAssertEqual(order.map { "\($0)" }, ["a", "b", "stray"])
    }
}
