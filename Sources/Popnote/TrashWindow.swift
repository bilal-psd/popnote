import AppKit
import PopnoteCore
import SwiftUI

/// Trash: deleted and expired notes, restorable until they age out.
final class TrashModel: ObservableObject {
    @Published var notes: [Note] = []
    private let store: NoteStore
    private let onRestore: (Note) -> Void

    init(store: NoteStore, onRestore: @escaping (Note) -> Void) {
        self.store = store
        self.onRestore = onRestore
        reload()
    }

    func reload() {
        notes = (try? store.trashedNotes()) ?? []
    }

    func restore(_ note: Note) {
        try? store.restore(id: note.id)
        reload()
        onRestore(note)
    }

    func emptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "\(notes.count) note(s) will be deleted permanently. This can't be undone."
        alert.addButton(withTitle: "Empty")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.emptyTrash()
        reload()
    }
}

struct TrashView: View {
    @ObservedObject var model: TrashModel
    private let retentionDays = Int(Settings.trashRetention / 86400)
    private let relative = RelativeDateTimeFormatter()

    var body: some View {
        VStack(spacing: 0) {
            if model.notes.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "trash",
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
                Button("Empty Trash…") { model.emptyTrash() }
                    .disabled(model.notes.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 360, minHeight: 280)
        .font(Font(Fonts.mono(12) as CTFont))
    }
}

final class TrashWindowController: NSWindowController {
    let model: TrashModel

    init(model: TrashModel) {
        self.model = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: TrashView(model: model)))
        window.title = "Trash"
        window.setContentSize(NSSize(width: 420, height: 380))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
