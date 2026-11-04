import AppKit

extension ConnectedServerViewController {
    /// VoiceOver's cursor and the outline's keyboard selection can be on different
    /// rows. Resolve the action's own row again; never fall back to selectedNode.
    func rowAccessibilityAction(name: String, node: ServerTreeNode,
        handler: @escaping (ConnectedServerViewController, ServerTreeNode) -> Void
    ) -> NSAccessibilityCustomAction {
        let serverID = session.savedServer.id
        return NSAccessibilityCustomAction(name: name) { [weak self] in
            guard let self, self.session.savedServer.id == serverID,
                  let current = self.currentAccessibilityNode(matching: node) else { return false }
            handler(self, current)
            return true
        }
    }

    func currentAccessibilityNode(matching node: ServerTreeNode) -> ServerTreeNode? {
        switch node {
        case .user(let original):
            guard let current = session.findUserByID(original.id),
                  current.username == original.username,
                  current.nickname == original.nickname,
                  current.channelID == original.channelID else { return nil }
            return .user(current)
        case .channel(let original):
            guard let current = session.findChannelByID(original.id),
                  current.pathComponents == original.pathComponents,
                  current.name == original.name else { return nil }
            return .channel(current)
        }
    }
}
