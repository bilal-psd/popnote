import AppKit
import PopnoteCore
import SwiftUI

/// The Void: deleted and expired notes, restorable until they age out.
final class VoidModel: ObservableObject {
    @Published var notes: [Note] = []
    private let store: NoteStore
    private let onRestore: (Note) -> Void

    init(store: NoteStore, onRestore: @escaping (Note) -> Void) {
        self.store = store
        self.onRestore = onRestore
        reload()
    }

    func reload() {
        notes = (try? store.voidNotes()) ?? []
    }

    func restore(_ note: Note) {
        try? store.restore(id: note.id)
        reload()
        onRestore(note)
    }

    func emptyVoid() {
        let alert = NSAlert()
        alert.messageText = "Empty The Void?"
        alert.informativeText = "\(notes.count) note(s) will be deleted permanently. This can't be undone."
        alert.addButton(withTitle: "Empty")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.emptyVoid()
        reload()
    }
}

struct VoidView: View {
    @ObservedObject var model: VoidModel
    private let retentionDays = Int(Settings.voidRetention / 86400)
    private let relative = RelativeDateTimeFormatter()

    var body: some View {
        VStack(spacing: 0) {
            if model.notes.isEmpty {
                ContentUnavailableView("The Void is empty", systemImage: "circle.dashed",
                                       description: Text("Deleted and expired notes wait here for \(retentionDays) days."))
            } else {
                List(model.notes) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.preview).lineLimit(1)
                            Text("deleted \(relative.localizedString(for: note.deletedAt ?? Date(), relativeTo: Date()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { model.restore(note) }
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Text("Notes are deleted for good after \(retentionDays) days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Empty The Void…") { model.emptyVoid() }
                    .disabled(model.notes.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 360, minHeight: 280)
        .font(Font(Fonts.mono(12) as CTFont))
    }
}

final class VoidWindowController: NSWindowController {
    let model: VoidModel

    init(model: VoidModel) {
        self.model = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: VoidView(model: model)))
        window.title = "The Void"
        window.setContentSize(NSSize(width: 420, height: 380))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
