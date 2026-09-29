import AppKit
import PopnoteCore

/// A terminal colour scheme. Every colour adapts to light and dark mode.
struct Theme {
    let id: String
    let name: String
    let background: NSColor
    /// Status line and command palette.
    let surface: NSColor
    let text: NSColor
    /// Comments, hints, unchecked boxes.
    let dim: NSColor
    let accent: NSColor
    /// Checked items.
    let ok: NSColor
    /// Borders, paper lines, selection outlines.
    let rule: NSColor

    static let all: [Theme] = [
        Theme(id: "tokyonight", name: "Tokyo Night",
              background: adaptive(0xE1E2E7, 0x1A1B26), surface: adaptive(0xD0D5E3, 0x16161E),
              text: adaptive(0x3760BF, 0xC0CAF5), dim: adaptive(0x848CB5, 0x565F89),
              accent: adaptive(0x2E7DE9, 0x7AA2F7), ok: adaptive(0x587539, 0x9ECE6A), rule: adaptive(0xC4C8DA, 0x292E42)),
        Theme(id: "gruvbox", name: "Gruvbox",
              background: adaptive(0xFBF1C7, 0x282828), surface: adaptive(0xEBDBB2, 0x1D2021),
              text: adaptive(0x3C3836, 0xEBDBB2), dim: adaptive(0x928374, 0x928374),
              accent: adaptive(0xB57614, 0xFABD2F), ok: adaptive(0x79740E, 0xB8BB26), rule: adaptive(0xD5C4A1, 0x3C3836)),
        Theme(id: "catppuccin", name: "Catppuccin",
              background: adaptive(0xEFF1F5, 0x1E1E2E), surface: adaptive(0xE6E9EF, 0x181825),
              text: adaptive(0x4C4F69, 0xCDD6F4), dim: adaptive(0x9CA0B0, 0x6C7086),
              accent: adaptive(0x8839EF, 0xCBA6F7), ok: adaptive(0x40A02B, 0xA6E3A1), rule: adaptive(0xCCD0DA, 0x313244)),
        Theme(id: "solarized", name: "Solarized",
              background: adaptive(0xFDF6E3, 0x002B36), surface: adaptive(0xEEE8D5, 0x073642),
              text: adaptive(0x586E75, 0x93A1A1), dim: adaptive(0x93A1A1, 0x586E75),
              accent: adaptive(0x268BD2, 0xB58900), ok: adaptive(0x859900, 0x859900), rule: adaptive(0xE6DFC8, 0x0A3F4C)),
        Theme(id: "nord", name: "Nord",
              background: adaptive(0xECEFF4, 0x2E3440), surface: adaptive(0xE5E9F0, 0x272C36),
              text: adaptive(0x2E3440, 0xD8DEE9), dim: adaptive(0x7B88A1, 0x616E88),
              accent: adaptive(0x5E81AC, 0x88C0D0), ok: adaptive(0x5F8746, 0xA3BE8C), rule: adaptive(0xD8DEE9, 0x3B4252)),
        Theme(id: "system", name: "System",
              background: .textBackgroundColor, surface: .windowBackgroundColor,
              text: .textColor, dim: .secondaryLabelColor,
              accent: .controlAccentColor, ok: .systemGreen, rule: .separatorColor),
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

/// Monospaced fonts. A Nerd Font unlocks icons and powerline separators;
/// without one, Popnote falls back to plain ASCII.
enum Fonts {
    /// Tried in order when no font is chosen in Settings.
    private static let preferred = ["JetBrainsMono Nerd Font Mono", "JetBrainsMonoNL Nerd Font Mono",
                                    "FiraCode Nerd Font Mono", "Hack Nerd Font Mono", "MesloLGS NF"]

    /// Installed fixed-width families, for the Settings picker.
    static var installedMonospaced: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            NSFont(name: family, size: 12)?.isFixedPitch == true
                || NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12)?.isFixedPitch == true
        }
    }

    /// Resolved once per Settings value; status line redraws call this a lot.
    private static var cached: (choice: String?, family: String?)?

    static func family() -> String? {
        let choice = Settings.font
        if let cached, cached.choice == choice { return cached.family }
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        let family = choice.flatMap { installed.contains($0) ? $0 : nil }
            ?? preferred.first(where: installed.contains)
            ?? installed.sorted().first(where: { $0.contains("Nerd Font Mono") })
        cached = (choice, family)
        return family
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let appKitWeight = weight == .bold ? 9 : weight == .medium ? 6 : 5
        if let family = family(),
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: appKitWeight, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static var hasNerdGlyphs: Bool {
        guard let family = family() else { return false }
        return family.contains("Nerd Font") || family.hasSuffix(" NF")
    }
}

/// Icons from the Nerd Font set, with ASCII stand-ins.
enum Glyph {
    static var unchecked: String { Fonts.hasNerdGlyphs ? "\u{F096}" : "[ ]" }
    static var checked: String { Fonts.hasNerdGlyphs ? "\u{F14A}" : "[x]" }
    static var bullet: String { Fonts.hasNerdGlyphs ? "\u{F444}" : "*" }
    static var pin: String { Fonts.hasNerdGlyphs ? "\u{F08D}" : "^" }
    static var clock: String { Fonts.hasNerdGlyphs ? "\u{F017}" : "~" }
    static var search: String { Fonts.hasNerdGlyphs ? "\u{F002}" : "/" }
    static var note: String { Fonts.hasNerdGlyphs ? "\u{F15C}" : "note" }
    static var list: String { Fonts.hasNerdGlyphs ? "\u{F0CA}" : "list" }
    static var code: String { Fonts.hasNerdGlyphs ? "\u{F121}" : "code" }
    static var top: String { Fonts.hasNerdGlyphs ? "\u{F0D8}" : "top" }
    /// Powerline separators (solid right, solid left).
    static var separatorRight: String? { Fonts.hasNerdGlyphs ? "\u{E0B0}" : nil }
    static var separatorLeft: String? { Fonts.hasNerdGlyphs ? "\u{E0B2}" : nil }
}
