import Foundation
import Testing
@testable import PopnoteCore

private func note(_ body: String) -> Note {
    Note(id: 1, body: body, createdAt: Date(), updatedAt: Date())
}

@Test func titleSkipsBlankLinesAndMarkers() {
    #expect(NoteText.title(of: note("\n\n- [ ] eggs\n- [ ] milk")) == "eggs")
    #expect(NoteText.title(of: note("  \n")) == "empty note")
    #expect(NoteText.title(of: note(String(repeating: "a", count: 80))).count == 61)
}
