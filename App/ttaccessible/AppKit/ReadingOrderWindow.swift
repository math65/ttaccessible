//
//  ReadingOrderWindow.swift
//  ttaccessible
//

import AppKit

/// The main window, read by VoiceOver in the order its content is built, not the order it
/// sits on screen.
///
/// VoiceOver walks a window through AXChildrenInNavigationOrder, and AppKit fills that by
/// sorting the window's elements on their position, top to bottom then left to right. For a
/// single column that is the same thing. For the connected window's two panes it is not:
/// the content pane's first level sits level with the server name, so VO-Right went server
/// name, output volume, "Connected as…", input volume… (measured, with VoiceOver itself).
/// AXChildren was right all along — the panes' contents in order, which
/// ConnectedServerSplitView sees to.
///
/// So the window keeps AppKit's order for its own chrome (the title-bar buttons, the title,
/// the toolbar), and within the slots AppKit gave the content, puts the content back in
/// AXChildren order. (The override itself is in NavigationOrderWindow.m: see there why.)
final class ReadingOrderWindow: NavigationOrderWindow {
    override func navigationOrder(fromAppKitOrder order: [Any]) -> [Any] {
        Self.readingOrder(spatial: order, children: accessibilityChildren() ?? [], isContent: isContentElement)
    }

    private func isContentElement(_ element: Any) -> Bool {
        guard let contentView else { return false }
        if let view = element as? NSView {
            return view.isDescendant(of: contentView)
        }
        // Labels and buttons reach the list as their cells.
        if let cell = element as? NSCell {
            return cell.controlView?.isDescendant(of: contentView) ?? false
        }
        // An element that isn't a view (the mixer's overlay rows, say) belongs to the view
        // that hosts it.
        var parent = (element as? NSAccessibilityProtocol)?.accessibilityParent()
        while let current = parent {
            if let view = current as? NSView { return view.isDescendant(of: contentView) }
            parent = (current as? NSAccessibilityProtocol)?.accessibilityParent()
        }
        return false
    }

    /// `spatial` with its content elements re-ordered as they come in `children`; every
    /// other element keeps its place.
    static func readingOrder(spatial: [Any], children: [Any], isContent: (Any) -> Bool) -> [Any] {
        let rank: (Any) -> Int = { element in
            children.firstIndex { ($0 as AnyObject) === (element as AnyObject) } ?? Int.max
        }
        var content = spatial.filter(isContent)
        // Stable: two elements AXChildren doesn't know keep AppKit's order between them.
        content = content.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        var next = content.makeIterator()
        return spatial.map { isContent($0) ? next.next()! : $0 }
    }
}
