//
//  SessionHistoryTableCellView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

final class SessionHistoryTableCellView: NSTableCellView {
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(message: String, accessibilityText: String) {
        messageLabel.stringValue = message
        setAccessibilityLabel(accessibilityText)
    }

    private func configureUI() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setAccessibilityElement(false)
        messageLabel.setAccessibilityHidden(true)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
}
