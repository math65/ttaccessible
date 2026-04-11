//
//  ChannelChatTableCellView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

/// NSTextView subclass that only consumes mouse clicks on links,
/// letting the table view handle row selection for clicks on plain text.
private final class LinkTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        if linkIndex(for: event) != nil {
            super.mouseDown(with: event)
        } else {
            nextResponder?.mouseDown(with: event)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let localPoint = convert(point, from: superview)
        guard let layoutManager, let textContainer = textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard boundingRect.contains(localPoint) else { return nil }
        let charIndex = layoutManager.characterIndex(for: localPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard charIndex < textStorage.length,
              textStorage.attribute(.link, at: charIndex, effectiveRange: nil) != nil else {
            return nil
        }
        return super.hitTest(point)
    }

    private func linkIndex(for event: NSEvent) -> Int? {
        guard let textStorage, textStorage.length > 0,
              let layoutManager, let textContainer = textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard charIndex < textStorage.length,
              textStorage.attribute(.link, at: charIndex, effectiveRange: nil) != nil else {
            return nil
        }
        return charIndex
    }
}

final class ChannelChatTableCellView: NSTableCellView {
    private let senderLabel = NSTextField(labelWithString: "")
    private let messageTextView = LinkTextView()

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

        messageTextView.isEditable = false
        messageTextView.isSelectable = true
        messageTextView.drawsBackground = false
        messageTextView.textContainerInset = .zero
        messageTextView.textContainer?.lineFragmentPadding = 0
        messageTextView.font = .preferredFont(forTextStyle: .body)
        messageTextView.isVerticallyResizable = false
        messageTextView.isHorizontallyResizable = false
        messageTextView.textContainer?.widthTracksTextView = true
        messageTextView.setAccessibilityElement(false)
        messageTextView.setAccessibilityHidden(true)

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
