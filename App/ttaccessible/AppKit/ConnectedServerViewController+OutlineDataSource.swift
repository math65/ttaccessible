//
//  ConnectedServerViewController+OutlineDataSource.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit

// MARK: - Tree Navigation Helpers

extension ConnectedServerViewController {
    func rootNode(at index: Int) -> ServerTreeNode {
        .channel(session.rootChannels[index])
    }

    func childNode(at index: Int, for node: ServerTreeNode) -> ServerTreeNode {
        switch node {
        case .channel(let channel):
            if index < channel.users.count {
                return .user(channel.users[index])
            }
            return .channel(channel.children[index - channel.users.count])
        case .user:
            fatalError("A user node has no children")
        }
    }

    func numberOfChildren(for node: ServerTreeNode?) -> Int {
        guard let node else {
            return session.rootChannels.count
        }

        switch node {
        case .channel(let channel):
            return channel.children.count + channel.users.count
        case .user:
            return 0
        }
    }

    func isExpandable(_ node: ServerTreeNode) -> Bool {
        switch node {
        case .channel(let channel):
            return channel.children.isEmpty == false || channel.users.isEmpty == false
        case .user:
            return false
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension ConnectedServerViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        numberOfChildren(for: item as? ServerTreeNode)
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? ServerTreeNode {
            return childNode(at: index, for: node)
        }
        return rootNode(at: index)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? ServerTreeNode else {
            return false
        }
        return isExpandable(node)
    }
}
