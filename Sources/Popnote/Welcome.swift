import AppKit
import PopnoteCore
import ServiceManagement
import SwiftUI

/// First-launch window: Popnote has no Dock icon and opens with a hotkey, so
/// without this a new user would see nothing happen after opening the app.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let seenKey = "welcomeSeen"

    static var hasBeenSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    private let onDone: () -> Void

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView { [weak self] in self?.close() })
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        onDone()
    }
}

private struct WelcomeView: View {
    let start: () -> Void
    @State private var openAtLogin = true

    private var keep: String {
        let hours = Int(PopnoteCore.Settings.noteTTL / 3600)
        return hours % 24 == 0 ? "\(hours / 24) day\(hours == 24 ? "" : "s")" : "\(hours) hours"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Popnote is running").font(.title2.bold())
                    Text("It lives in your menu bar, not the Dock.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Tip(key: PopnoteCore.Settings.hotkeyLabel, text: "opens and closes your notes from any app")
                Tip(key: "⌘", text: "hold it in a note to see every shortcut")
                Tip(key: "⌘P", text: "pins a note. Unpinned notes delete themselves after \(keep).")
            }
            Toggle("Open Popnote at login", isOn: $openAtLogin)
            HStack {
                Spacer()
                Button("Start writing") {
                    if openAtLogin { try? SMAppService.mainApp.register() }
                    start()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 22)
        .frame(width: 400)
    }
}

private struct Tip: View {
    let key: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(.body, design: .monospaced).bold())
                .frame(minWidth: 34)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            Text(text)
        }
    }
}

/// Settings from before the app identifier changed (com.popnote.Popnote).
enum LegacyDefaults {
    private static let oldDomain = "com.popnote.Popnote"
    private static let migratedKey = "migratedFromOldIdentifier"

    /// Copies the old settings across once. Notes aren't affected: they live
    /// in Application Support, not in the preferences.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != oldDomain, !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        // They've used Popnote already; no need to introduce it.
        defaults.set(true, forKey: WelcomeWindowController.seenKey)
    }
}
