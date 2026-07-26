//
//  SavedServersTableView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

protocol SavedServersTableViewActionDelegate: AnyObject {
    func savedServersTableViewDidRequestDelete(_ tableView: SavedServersTableView)
    func savedServersTableViewDidRequestConnect(_ tableView: SavedServersTableView)
    func savedServersTableView(_ tableView: SavedServersTableView, menuForRow row: Int) -> NSMenu?
}

final class SavedServersTableView: NSTableView {
    weak var actionDelegate: SavedServersTableViewActionDelegate?

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let row = row(at: location)

        guard row >= 0 else {
            return nil
        }

        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return actionDelegate?.savedServersTableView(self, menuForRow: row)
    }

    // VO-Espace sur le tableau (sans interagir) rejoint la ligne sélectionnée,
    // exactement comme la touche Entrée. Sans cela, VO-Espace n'agit que lorsqu'on
    // a « interagi » avec le tableau (curseur VoiceOver descendu sur une cellule).
    override func accessibilityPerformPress() -> Bool {
        actionDelegate?.savedServersTableViewDidRequestConnect(self)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 36 || event.keyCode == 76 {
            actionDelegate?.savedServersTableViewDidRequestConnect(self)
            return
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 51 || event.keyCode == 117 {
            actionDelegate?.savedServersTableViewDidRequestDelete(self)
            return
        }

        super.keyDown(with: event)
    }
}
