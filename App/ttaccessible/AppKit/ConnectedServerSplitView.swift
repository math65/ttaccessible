//
//  ConnectedServerSplitView.swift
//  ttaccessible
//
//  The connected window's two panes: a sidebar (server identity, microphone, channel
//  tree) and the content pane (video, mixer, chat, history). Split out of
//  ConnectedServerViewController so the sizing rules live in one place.
//
//  The sidebar keeps its width when the window is resized — the content pane is what
//  should grow — and the user's own drag is remembered through the split view's
//  autosave name.
//

#if os(macOS)
import AppKit

final class ConnectedServerSplitView: NSSplitView, NSSplitViewDelegate {
    private static let minimumSidebarWidth: CGFloat = 240
    private static let maximumSidebarWidth: CGFloat = 460
    static let defaultSidebarWidth: CGFloat = 340

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
    }

    required init?(coder: NSCoder) { nil }

    /// Restore a sane width the first time, when no autosaved position exists yet.
    func applyDefaultPositionIfNeeded() {
        guard arrangedSubviews.count == 2 else { return }
        let width = arrangedSubviews[0].frame.width
        guard width < Self.minimumSidebarWidth || width > Self.maximumSidebarWidth else { return }
        setPosition(Self.defaultSidebarWidth, ofDividerAt: 0)
    }

    func splitView(_ splitView: NSSplitView,
                   constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        Self.minimumSidebarWidth
    }

    func splitView(_ splitView: NSSplitView,
                   constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(Self.maximumSidebarWidth, proposedMaximumPosition)
    }

    /// Only the content pane absorbs a window resize.
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view !== arrangedSubviews.first
    }

    // MARK: - Invisible to VoiceOver

    // The split is a VISUAL arrangement. It changed nothing about what the window holds
    // or the order it holds it in — but AppKit exposes it anyway, as an AXSplitGroup
    // wrapping the whole window plus an AXSplitter between the panes. So a window that
    // used to be a flat walk became a group to step into and a divider to step past,
    // for a change that was only ever about where things sit on screen.
    //
    // Take the split out of the tree. Ignoring the view alone is not enough: AppKit
    // synthesises the divider as one of its accessibility children, so it would simply
    // rise a level and still be met. Returning the arranged subviews — and only those —
    // leaves the two panes' own contents to rise to the window, in the same order they
    // had before the split existed. That is their AXChildren order; VoiceOver walks the
    // window's navigation order, which AppKit sorts by position and which would interleave
    // the panes — ReadingOrderWindow puts it back.
    override func isAccessibilityElement() -> Bool { false }

    // Through the unignored walk, not raw: handing back the two container views
    // themselves put each pane in the tree as an AXUnknown group, which is one wrapper
    // worse than the AXSplitGroup it replaced (measured). unignoredChildren flattens
    // them, so what rises is their contents.
    override func accessibilityChildren() -> [Any]? {
        NSAccessibility.unignoredChildren(from: arrangedSubviews)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }
}
#endif
