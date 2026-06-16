//
//  AppDelegate+NewInstance.swift
//  ttaccessible
//

import AppKit

@MainActor
extension AppDelegate {
    /// Show the picker that lets the user launch a separate process bound to
    /// another profile. Triggered from the "New Instance…" menu item.
    func openNewInstanceDialog() {
        let registry = ProfileRegistry.shared
        let existing = registry.listAll()
        let currentSlug = ProfileContext.current.slug

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("profile.newInstance.title")
        alert.informativeText = L10n.text("profile.newInstance.message")
        alert.addButton(withTitle: L10n.text("profile.newInstance.launch"))
        alert.addButton(withTitle: L10n.text("profile.newInstance.createNew"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.setAccessibilityLabel(L10n.text("profile.newInstance.picker.accessibilityLabel"))
        for entry in existing {
            let title: String
            if entry.slug == currentSlug {
                title = L10n.format("profile.newInstance.picker.currentSuffix", entry.displayName)
            } else {
                title = entry.displayName
            }
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = entry.slug
        }
        if popup.numberOfItems == 0 {
            // Should never happen — the registry always includes the default entry.
            popup.addItem(withTitle: ProfileContext.defaultDisplayName)
            popup.lastItem?.representedObject = ProfileContext.defaultSlug
        }

        // Default the picker to the first non-current profile if any exist.
        if let firstOther = existing.firstIndex(where: { $0.slug != currentSlug }) {
            popup.selectItem(at: firstOther)
        }

        alert.accessoryView = popup

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            guard let slug = popup.selectedItem?.representedObject as? String else { return }
            launchInstance(forSlug: slug)
        case .alertSecondButtonReturn:
            promptCreateAndLaunchProfile()
        default:
            return
        }
    }

    private func promptCreateAndLaunchProfile() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("profile.create.title")
        alert.informativeText = L10n.text("profile.create.message")
        alert.addButton(withTitle: L10n.text("profile.create.launch"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = L10n.text("profile.create.placeholder")
        field.setAccessibilityLabel(L10n.text("profile.create.field.accessibilityLabel"))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let rawName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawName.isEmpty == false else {
            presentNewInstanceError(message: L10n.text("profile.create.error.empty"))
            return
        }

        let slug = ProfileContext.normalizeSlug(rawName)
        guard slug.isEmpty == false else {
            presentNewInstanceError(message: L10n.text("profile.create.error.invalid"))
            return
        }
        guard slug != ProfileContext.defaultSlug else {
            presentNewInstanceError(message: L10n.text("profile.create.error.reservedDefault"))
            return
        }

        guard let entry = ProfileRegistry.shared.register(displayName: rawName) else {
            presentNewInstanceError(message: L10n.text("profile.create.error.invalid"))
            return
        }
        launchInstance(forSlug: entry.slug)
    }

    private func launchInstance(forSlug rawSlug: String) {
        let slug = ProfileContext.normalizeSlug(rawSlug)

        // Launching another process bound to the same profile would have two
        // processes writing into the same UserDefaults suite — that's almost
        // always a mistake, especially for the Default profile, which IS the
        // current process. Refuse instead of silently double-launching.
        if slug == ProfileContext.current.slug {
            presentNewInstanceError(message: L10n.format(
                "profile.newInstance.error.sameProfile",
                ProfileContext.current.displayName
            ))
            return
        }

        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = ["-profile", slug]

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.presentNewInstanceError(message: error.localizedDescription)
            }
        }
    }

    private func presentNewInstanceError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("profile.newInstance.error.title")
        alert.informativeText = message
        alert.runModal()
    }
}
