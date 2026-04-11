//
//  ConnectedServerViewController+OutlineDataSource.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

// MARK: - Tree Navigation Helpers

extension ConnectedServerViewController {
    func rootNode(at index: Int) -> ServerTreeNode? {
        guard index >= 0, index < session.rootChannels.count else { return nil }
        return .channel(session.rootChannels[index])
    }

    func childNode(at index: Int, for node: ServerTreeNode) -> ServerTreeNode? {
        switch node {
        case .channel(let channel):
            if index >= 0, index < channel.users.count {
                return .user(channel.users[index])
            }
            let childIndex = index - channel.users.count
            guard childIndex >= 0, childIndex < channel.children.count else {
                return nil
            }
            return .channel(channel.children[childIndex])
        case .user:
            return nil
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
        if let node = item as? ServerTreeNode,
           let child = childNode(at: index, for: node) {
            return child
        }
        return rootNode(at: index) as Any
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? ServerTreeNode else {
            return false
        }
        return isExpandable(node)
    }
}
