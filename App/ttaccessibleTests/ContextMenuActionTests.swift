import XCTest
@testable import ttaccessible

@MainActor
final class ContextMenuActionTests: XCTestCase {
    private final class CancelledMenu: NSMenu {
        var wasOpened = false
        override func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
            wasOpened = true
            return false // The user dismissed an opened menu without choosing an item.
        }
    }
    private final class Source: NSObject, NSOutlineViewDataSource, ConnectedServerOutlineViewActionDelegate {
        let node = NSObject()
        let menu = CancelledMenu()
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 1 : 0 }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { node }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
        func connectedServerOutlineViewDidRequestDefaultAction(_ outlineView: ConnectedServerOutlineView) {}
        func connectedServerOutlineView(_ outlineView: ConnectedServerOutlineView, menuForRow row: Int) -> NSMenu? { menu }
    }
    func testCancellingAnOpenedMenuStillReportsThatTheAccessibilityActionTriggered() {
        let source = Source()
        let outline = ConnectedServerOutlineView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        outline.addTableColumn(NSTableColumn(identifier: .init("name")))
        outline.dataSource = source; outline.actionDelegate = source
        let window = NSWindow(contentRect: outline.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = outline
        outline.reloadData(); outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(outline.accessibilityPerformShowMenu())
        XCTAssertTrue(source.menu.wasOpened)
        outline.deselectAll(nil)
        source.menu.wasOpened = false
        XCTAssertFalse(outline.accessibilityPerformShowMenu())
        XCTAssertFalse(source.menu.wasOpened)
    }
}
