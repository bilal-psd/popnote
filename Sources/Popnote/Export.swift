import AppKit
import PopnoteCore
import UniformTypeIdentifiers

/// Getting a note out of Popnote: clipboard, files, and other note apps.
enum Export {
    static func copyText(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Exporter.plainText(of: note), forType: .string)
    }

    enum FileFormat {
        case text, markdown, pdf

        var type: UTType {
            switch self {
            case .text: return .plainText
            case .markdown: return UTType(filenameExtension: "md") ?? .plainText
            case .pdf: return .pdf
            }
        }
    }

    static func save(_ note: Note, as format: FileFormat, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = Exporter.fileName(of: note)
        panel.canCreateDirectories = true
        let write: (URL) -> Void = { url in
            do {
                switch format {
                case .text: try Exporter.plainText(of: note).write(to: url, atomically: true, encoding: .utf8)
                case .markdown: try Exporter.markdown(of: note).write(to: url, atomically: true, encoding: .utf8)
                case .pdf: writePDF(note, to: url)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window {
            panel.beginSheetModal(for: window) { if $0 == .OK, let url = panel.url { write(url) } }
        } else if panel.runModal() == .OK, let url = panel.url {
            write(url)
        }
    }

    /// Lays the note out in an off-screen editor (so checkboxes render) and
    /// prints it to a PDF, split into pages.
    static func writePDF(_ note: Note, to url: URL) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = EditorTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.configure()
        view.applyAppearance(theme: Theme.named("system"), paper: .blank, fontSize: 12)
        view.textContainerInset = .zero
        view.appearance = NSAppearance(named: .aqua)
        view.string = Exporter.plainText(of: note)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { _ = operation.run() }
    }

    // MARK: Other apps

    /// Creates a note in Apple Notes' default folder. macOS asks once for
    /// permission to control Notes.
    static func sendToAppleNotes(_ note: Note) {
        let script = """
            tell application "Notes"
                make new note with properties {name:"\(appleScriptEscape(Exporter.title(of: note)))", body:"\(appleScriptEscape(Exporter.notesHTML(of: note)))"}
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard let error else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn't send the note to Apple Notes."
        if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
            alert.informativeText = "Popnote isn't allowed to control Notes. Turn it on in System Settings › Privacy & Security › Automation."
        } else {
            alert.informativeText = error[NSAppleScript.errorMessage] as? String ?? "Unknown error."
        }
        alert.runModal()
    }

    static func sendToObsidian(_ note: Note) {
        open(Exporter.obsidianURL(for: note, vault: Settings.obsidianVault), appName: "Obsidian")
    }

    static func sendToBear(_ note: Note) {
        open(Exporter.bearURL(for: note), appName: "Bear")
    }

    private static func open(_ url: URL?, appName: String) {
        guard let url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            let alert = NSAlert()
            alert.messageText = "\(appName) isn't installed."
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
