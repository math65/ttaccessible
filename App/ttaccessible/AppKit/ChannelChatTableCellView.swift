//
//  ChannelChatTableCellView.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit

final class ChannelChatTableCellView: NSTableCellView {
    private let senderLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(with message: ChannelChatMessage, formattedTime: String) {
        let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
        senderLabel.stringValue = "\(senderName), \(formattedTime)"
        messageLabel.stringValue = message.message
        setAccessibilityLabel(
            L10n.format(
                "connectedServer.chat.row.accessibilityLabel",
                senderName,
                message.message,
                formattedTime
            )
        )
    }

    func configure(with message: PrivateChatMessage, formattedTime: String) {
        let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
        senderLabel.stringValue = "\(senderName), \(formattedTime)"
        messageLabel.stringValue = message.message
        setAccessibilityLabel(
            L10n.format(
                "privateMessages.row.accessibilityLabel",
                senderName,
                message.message,
                formattedTime
            )
        )
    }

    private func configureUI() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        senderLabel.font = .preferredFont(forTextStyle: .subheadline)
        senderLabel.textColor = .secondaryLabelColor
        senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.setAccessibilityElement(false)
        senderLabel.setAccessibilityHidden(true)

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setAccessibilityElement(false)
        messageLabel.setAccessibilityHidden(true)

        let stack = NSStackView(views: [senderLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
}
