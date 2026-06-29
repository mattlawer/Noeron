//
//  ViewExtensions.swift
//  Noeron
//
//  Small cross-platform view helpers.
//

import SwiftUI

extension View {
    /// Applies a minimum window size on macOS only. On iOS/iPadOS a fixed minWidth
    /// would force sheet/modal content wider than the screen and clip it
    /// horizontally — so on those platforms this is a no-op.
    @ViewBuilder
    func macWindowFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
        #endif
    }
}
