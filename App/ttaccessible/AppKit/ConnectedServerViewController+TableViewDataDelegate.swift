//
//  ConnectedServerViewController+TableViewDataDelegate.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit

// MARK: - Table View Helper Methods

extension ConnectedServerViewController {
    func chatAccessibilityText(for message: ChannelChatMessage) -> String {
        let timestamp = timeFormatter.string(from: message.receivedAt)
        let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
        return "\(senderName) : \(message.message), \(timestamp)"
    }

    func historyAccessibilityText(for entry: SessionHistoryEntry) -> String {
        "\(entry.message), \(timeFormatter.string(from: entry.timestamp))"
    }

    func height(for message: ChannelChatMessage, width: CGFloat) -> CGFloat {
        let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
        let senderHeight = NSAttributedString(
            string: "\(senderName), \(timeFormatter.string(from: message.receivedAt))",
            attributes: [.font: NSFont.preferredFont(forTextStyle: .subheadline)]
        ).boundingRect(
            with: NSSize(width: max(width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        let messageHeight = NSAttributedString(
            string: message.message,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).boundingRect(
            with: NSSize(width: max(width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        return ceil(senderHeight + messageHeight + 24)
    }

    func height(for entry: SessionHistoryEntry, width: CGFloat) -> CGFloat {
        let text = historyAccessibilityText(for: entry)
        let textHeight = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).boundingRect(
            with: NSSize(width: max(width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        return ceil(textHeight + 20)
    }
}

// MARK: - NSTableViewDataSource

extension ConnectedServerViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == chatTableView {
            return session.channelChatHistory.count
        }
        if tableView == historyTableView {
            return session.sessionHistory.count
        }
        return 0
    }
}

// MARK: - NSTableViewDelegate

extension ConnectedServerViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == chatTableView,
           session.channelChatHistory.indices.contains(row) {
            return height(for: session.channelChatHistory[row], width: tableView.bounds.width)
        }

        if tableView == historyTableView,
           session.sessionHistory.indices.contains(row) {
            return height(for: session.sessionHistory[row], width: tableView.bounds.width)
        }

        return tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == chatTableView,
           session.channelChatHistory.indices.contains(row) {
            let identifier = NSUserInterfaceItemIdentifier("ChannelChatCell")
            let view: ChannelChatTableCellView

            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? ChannelChatTableCellView {
                view = existing
            } else {
                view = ChannelChatTableCellView(frame: .zero)
                view.identifier = identifier
            }

            let message = session.channelChatHistory[row]
            view.configure(with: message, formattedTime: timeFormatter.string(from: message.receivedAt))
            return view
        }

        if tableView == historyTableView,
           session.sessionHistory.indices.contains(row) {
            let identifier = NSUserInterfaceItemIdentifier("SessionHistoryCell")
            let view: SessionHistoryTableCellView

            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? SessionHistoryTableCellView {
                view = existing
            } else {
                view = SessionHistoryTableCellView(frame: .zero)
                view.identifier = identifier
            }

            let entry = session.sessionHistory[row]
            view.configure(
                message: historyAccessibilityText(for: entry),
                accessibilityText: historyAccessibilityText(for: entry)
            )
            return view
        }

        return nil
    }
}
