//
//  ConnectedServerOutlineView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

protocol ConnectedServerOutlineViewActionDelegate: AnyObject {
    func connectedServerOutlineViewDidRequestDefaultAction(_ outlineView: ConnectedServerOutlineView)
    func connectedServerOutlineView(_ outlineView: ConnectedServerOutlineView, menuForRow row: Int) -> NSMenu?
}

final class ConnectedServerOutlineView: NSOutlineView {
    weak var actionDelegate: ConnectedServerOutlineViewActionDelegate?

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        return contextMenu(forRow: row(at: location))
    }

    func contextMenu(forRow row: Int) -> NSMenu? {
        guard row >= 0, row < numberOfRows else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return actionDelegate?.connectedServerOutlineView(self, menuForRow: row)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = contextMenu(forRow: selectedRow), window != nil else { return false }
        scrollRowToVisible(selectedRow)
        let rowRect = rect(ofRow: selectedRow)
        _ = menu.popUp(positioning: nil, at: NSPoint(x: rowRect.minX + 20, y: rowRect.maxY), in: self)
        // AX reports whether opening was triggered, even if the user cancelled.
        return true
    }

    // VO-Espace sur l'arbre (sans interagir) effectue l'action par défaut sur la ligne
    // sélectionnée, exactement comme la touche Entrée. Sans cela, VO-Espace n'agit que
    // lorsqu'on a « interagi » avec l'arbre (curseur VoiceOver descendu sur une cellule).
    override func accessibilityPerformPress() -> Bool {
        guard selectedRow >= 0, let actionDelegate else { return false }
        actionDelegate.connectedServerOutlineViewDidRequestDefaultAction(self)
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Standard keyboard context-menu shortcut; function flags vary by keyboard.
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if modifiers == .shift, event.keyCode == 109 { // Shift-F10
            _ = accessibilityPerformShowMenu()
            return
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 36 || event.keyCode == 76 {
            actionDelegate?.connectedServerOutlineViewDidRequestDefaultAction(self)
            return
        }

        super.keyDown(with: event)
    }
}
