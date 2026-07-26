//
//  ViewCompat.swift
//  ttaccessible
//

import SwiftUI

extension View {
    /// `onChange` that also runs on macOS 12: the two-parameter variant the
    /// app used is macOS 14+, and the pre-14 variant is deprecated on 14+.
    /// This picks the right one at runtime so neither warning nor
    /// availability error appears at either end.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}
