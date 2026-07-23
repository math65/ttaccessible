//
//  MoveUsersViewController.swift
//  ttaccessible
//
//  Accessible bulk "move users to another channel" sheet: a VoiceOver-navigable
//  checklist of users plus a target-channel picker. Used for moving a whole
//  channel's occupants, or any subset of them, in one operation.
//

import AppKit

final class MoveUsersViewController: NSViewController {

    /// Called with the chosen user IDs and the destination channel ID when the
    /// user confirms. Not called on cancel or when nothing is selected.
    var onMove: (([Int32], Int32) -> Void)?

    private let candidates: [ConnectedServerUser]
    private let preselected: Set<Int32>
    private let channels: [ConnectedServerChannel]
    private let headerText: String

    private var checkboxes: [NSButton] = []
    private var channelPopup: NSPopUpButton!

    /// - Parameters:
    ///   - candidates: users that may be moved (already permission-filtered by the caller).
    ///   - preselected: IDs that should start checked.
    ///   - channels: destination channels (flattened, source channel already excluded).
    ///   - headerText: descriptive header, e.g. "Select users to move from “General”".
    init(candidates: [ConnectedServerUser],
         preselected: Set<Int32>,
         channels: [ConnectedServerChannel],
         headerText: String) {
        self.candidates = candidates
        self.preselected = preselected
        self.channels = channels
        self.headerText = headerText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 480))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupButtons()
    }

    // MARK: - Setup

    private func setupLayout() {
        let header = NSTextField(wrappingLabelWithString: headerText)
        header.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        header.translatesAutoresizingMaskIntoConstraints = false

        // Select all / deselect all
        let selectAllButton = NSButton(title: L10n.text("moveUsers.selectAll"),
                                       target: self, action: #selector(selectAllUsers))
        selectAllButton.bezelStyle = .rounded
        let deselectAllButton = NSButton(title: L10n.text("moveUsers.deselectAll"),
                                         target: self, action: #selector(deselectAllUsers))
        deselectAllButton.bezelStyle = .rounded
        let selectionButtons = NSStackView(views: [selectAllButton, deselectAllButton])
        selectionButtons.orientation = .horizontal
        selectionButtons.spacing = 8
        selectionButtons.translatesAutoresizingMaskIntoConstraints = false

        // Checkbox list
        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 4
        listStack.translatesAutoresizingMaskIntoConstraints = false

        for user in candidates {
            let checkbox = NSButton(checkboxWithTitle: user.displayName, target: nil, action: nil)
            checkbox.state = preselected.contains(user.id) ? .on : .off
            checkbox.tag = Int(user.id)
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            checkboxes.append(checkbox)
            listStack.addArrangedSubview(checkbox)
        }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        scrollView.setAccessibilityLabel(L10n.text("moveUsers.usersList"))
        let clipView = scrollView.contentView
        scrollView.documentView = listStack

        // Target channel picker
        let targetLabel = NSTextField(labelWithString: L10n.text("moveUsers.targetChannel"))
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        channelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        channelPopup.translatesAutoresizingMaskIntoConstraints = false
        channelPopup.setAccessibilityLabel(L10n.text("moveUsers.targetChannel"))
        channels.forEach { channelPopup.addItem(withTitle: $0.name) }
        let targetRow = NSStackView(views: [targetLabel, channelPopup])
        targetRow.orientation = .horizontal
        targetRow.spacing = 8
        targetRow.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(selectionButtons)
        view.addSubview(scrollView)
        view.addSubview(targetRow)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            selectionButtons.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            selectionButtons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            scrollView.topAnchor.constraint(equalTo: selectionButtons.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: targetRow.topAnchor, constant: -12),

            listStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor, constant: 4),
            listStack.topAnchor.constraint(equalTo: clipView.topAnchor, constant: 4),

            targetRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            targetRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            targetRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -52),
        ])
    }

    private func setupButtons() {
        let cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let moveButton = NSButton(title: L10n.text("moveUsers.confirm"), target: self, action: #selector(confirm))
        moveButton.bezelStyle = .rounded
        moveButton.keyEquivalent = "\r"
        moveButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(cancelButton)
        view.addSubview(moveButton)

        NSLayoutConstraint.activate([
            moveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            moveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cancelButton.trailingAnchor.constraint(equalTo: moveButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Actions

    @objc private func selectAllUsers() {
        checkboxes.forEach { $0.state = .on }
    }

    @objc private func deselectAllUsers() {
        checkboxes.forEach { $0.state = .off }
    }

    @objc private func confirm() {
        let selectedIDs = checkboxes.filter { $0.state == .on }.map { Int32($0.tag) }
        guard !selectedIDs.isEmpty else {
            NSAccessibility.post(
                element: view,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: L10n.text("moveUsers.noneSelected"),
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
            return
        }
        let targetIndex = channelPopup.indexOfSelectedItem
        guard targetIndex >= 0, targetIndex < channels.count else { return }
        let targetID = channels[targetIndex].id
        dismiss(nil)
        onMove?(selectedIDs, targetID)
    }

    @objc private func cancel() {
        dismiss(nil)
    }
}
