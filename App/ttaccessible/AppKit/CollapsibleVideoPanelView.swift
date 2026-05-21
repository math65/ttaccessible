//
//  CollapsibleVideoPanelView.swift
//  ttaccessible
//

import AppKit

@MainActor
protocol CollapsibleVideoPanelViewDelegate: AnyObject {
    func collapsibleVideoPanelViewDidToggleExpanded(_ view: CollapsibleVideoPanelView, expanded: Bool)
}

final class CollapsibleVideoPanelView: NSView {
    weak var delegate: CollapsibleVideoPanelViewDelegate?

    private(set) var isExpanded = true
    private let toggleButton = NSButton()
    private let videoFrameView = VideoFrameView()
    private var expandedHeightConstraint: NSLayoutConstraint?
    private var collapsedHeightConstraint: NSLayoutConstraint?

    var videoView: VideoFrameView { videoFrameView }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setExpanded(_ expanded: Bool, notifyDelegate: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        applyExpandedState()
        if notifyDelegate {
            delegate?.collapsibleVideoPanelViewDidToggleExpanded(self, expanded: expanded)
        }
    }

    func updateVideoState(_ state: VideoDisplayState) {
        if state.userID == 0 || state.frame == nil {
            videoFrameView.update(frame: nil)
            videoFrameView.setAccessibilitySourceLabel("")
        } else {
            videoFrameView.update(frame: state.frame)
            videoFrameView.setAccessibilitySourceLabel(
                L10n.format("video.panel.source.mediaFile", state.displayName)
            )
        }
    }

    private func configureUI() {
        toggleButton.bezelStyle = .disclosure
        toggleButton.setButtonType(.switch)
        toggleButton.title = L10n.text("video.panel.toggle.title")
        toggleButton.state = .on
        toggleButton.target = self
        toggleButton.action = #selector(toggleExpanded)
        toggleButton.setAccessibilityLabel(L10n.text("video.panel.toggle.accessibilityLabel"))

        videoFrameView.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(toggleButton)
        addSubview(videoFrameView)

        expandedHeightConstraint = videoFrameView.heightAnchor.constraint(equalToConstant: 220)
        collapsedHeightConstraint = videoFrameView.heightAnchor.constraint(equalToConstant: 0)
        collapsedHeightConstraint?.priority = .defaultHigh

        NSLayoutConstraint.activate([
            toggleButton.topAnchor.constraint(equalTo: topAnchor),
            toggleButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            toggleButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            videoFrameView.topAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: 6),
            videoFrameView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoFrameView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoFrameView.bottomAnchor.constraint(equalTo: bottomAnchor),
            expandedHeightConstraint!
        ])

        applyExpandedState()
    }

    private func applyExpandedState() {
        toggleButton.state = isExpanded ? .on : .off
        videoFrameView.isHidden = !isExpanded
        if isExpanded {
            collapsedHeightConstraint?.isActive = false
            expandedHeightConstraint?.isActive = true
        } else {
            expandedHeightConstraint?.isActive = false
            collapsedHeightConstraint?.isActive = true
        }
    }

    @objc private func toggleExpanded() {
        setExpanded(toggleButton.state == .on, notifyDelegate: true)
    }
}
