//
//  Theme.swift
//  Noeron
//
//  Colour resolution from hex + per-kind styling helpers for the UI layer.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255
            g = Double((rgb & 0x00FF0000) >> 16) / 255
            b = Double((rgb & 0x0000FF00) >> 8) / 255
            a = Double(rgb & 0x000000FF) / 255
        default:
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension EntityKind {
    var color: Color { Color(hex: colorHex) }
}

extension LinkKind {
    var color: Color { Color(hex: "#6E7681") }
}

enum Theme {
    static let accent = Color(hex: "#21C7BC")
    static let canvasBackground = Color(hex: "#0D1117")
    static let nodeStroke = Color(hex: "#30363D")
    static let panel = Color(hex: "#161B22")

    static func confidenceColor(_ c: Double) -> Color {
        switch c {
        case ..<0.34: return Color(hex: "#F85149")
        case ..<0.67: return Color(hex: "#E8A13A")
        default: return Color(hex: "#3FB950")
        }
    }
}
