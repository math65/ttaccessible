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
}
#endif
