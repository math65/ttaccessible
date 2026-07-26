//
//  XMLElement+ChildText.swift
//  ttaccessible
//
//  Shared helper for reading the trimmed text of a named child element. Used by
//  both TTFileService (.tt parsing) and BearWareWebLogin (bearware.dk responses)
//  so the XML extraction logic lives in one place.
//

import Foundation

extension XMLElement {
    /// Trimmed text content of the first child element with the given name, or
    /// an empty string when absent.
    func childText(named name: String) -> String {
        elements(forName: name).first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
