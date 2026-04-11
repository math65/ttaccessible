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
        let row = row(at: location)

        guard row >= 0 else {
            return nil
        }

        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return actionDelegate?.connectedServerOutlineView(self, menuForRow: row)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           event.keyCode == 36 || event.keyCode == 76 {
            actionDelegate?.connectedServerOutlineViewDidRequestDefaultAction(self)
            return
        }

        super.keyDown(with: event)
    }
}
