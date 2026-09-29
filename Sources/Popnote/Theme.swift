import AppKit

/// A colour theme. Every colour adapts to light and dark mode on its own.
struct Theme {
    let id: String
    let name: String
    let background: NSColor
    let text: NSColor
    let secondary: NSColor
    let accent: NSColor
    /// Lines on lined and grid paper.
    let rule: NSColor

    static let all: [Theme] = [
        Theme(id: "system", name: "System",
              background: .textBackgroundColor, text: .textColor, secondary: .secondaryLabelColor,
              accent: .controlAccentColor, rule: .separatorColor),
        Theme(id: "paper", name: "Paper",
              background: adaptive(0xFBF8F1, 0x2A2724), text: adaptive(0x2B2A28, 0xE8E3D9),
              secondary: adaptive(0x8A857C, 0x9A948A), accent: adaptive(0xD9822B, 0xE0A050),
              rule: adaptive(0xE9E2D2, 0x3A3632)),
        Theme(id: "graphite", name: "Graphite",
              background: adaptive(0xF4F4F5, 0x1C1C1E), text: adaptive(0x1D1D1F, 0xE5E5E7),
              secondary: adaptive(0x86868B, 0x8E8E93), accent: adaptive(0x5E5CE6, 0x7D7AFF),
              rule: adaptive(0xE3E3E6, 0x2E2E31)),
        Theme(id: "solarized", name: "Solarized",
              background: adaptive(0xFDF6E3, 0x002B36), text: adaptive(0x586E75, 0x93A1A1),
              secondary: adaptive(0x93A1A1, 0x586E75), accent: adaptive(0x268BD2, 0x2AA198),
              rule: adaptive(0xEEE8D5, 0x073642)),
        Theme(id: "mint", name: "Mint",
              background: adaptive(0xF2FBF6, 0x15201B), text: adaptive(0x1F3A2E, 0xD6EFE3),
              secondary: adaptive(0x6B8F7E, 0x7FA592), accent: adaptive(0x2FA36B, 0x4CC38A),
              rule: adaptive(0xDDF0E5, 0x22322A)),
    ]

    static func named(_ id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    private static func adaptive(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? hex(dark) : hex(light)
        }
    }

    private static func hex(_ value: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

enum Paper: String, CaseIterable {
    case blank, lined, grid

    var name: String { rawValue.capitalized }
}
