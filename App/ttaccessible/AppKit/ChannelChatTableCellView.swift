//
//  ChannelChatTableCellView.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit

final class ChannelChatTableCellView: NSTableCellView {
    private let senderLabel = NSTextField(labelWithString: "")
    private let messageTextView: NSTextView = {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityElement(false)
        textView.setAccessibilityHidden(true)
        return textView
    }()

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
        setMessageText(message.message)
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
        setMessageText(message.message)
        setAccessibilityLabel(
            L10n.format(
                "privateMessages.row.accessibilityLabel",
                senderName,
                message.message,
                formattedTime
            )
        )
    }

    private func setMessageText(_ text: String) {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let detector {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url {
                    attributed.addAttributes([
                        .link: url,
                        .cursor: NSCursor.pointingHand
                    ], range: match.range)
                }
            }
        }

        messageTextView.textStorage?.setAttributedString(attributed)
    }

    private func configureUI() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        senderLabel.font = .preferredFont(forTextStyle: .subheadline)
        senderLabel.textColor = .secondaryLabelColor
        senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.setAccessibilityElement(false)
        senderLabel.setAccessibilityHidden(true)

        messageTextView.translatesAutoresizingMaskIntoConstraints = false
        senderLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [senderLabel, messageTextView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            messageTextView.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }
}
