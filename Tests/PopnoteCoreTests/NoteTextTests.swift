import Foundation
import Testing
@testable import PopnoteCore

private func note(_ body: String) -> Note {
    Note(id: 1, body: body, createdAt: Date(), updatedAt: Date())
}

@Test func keywordLineIsLeftOut() {
    #expect(NoteText.content(of: note("list\n- [ ] eggs")) == "- [ ] eggs")
    #expect(NoteText.content(of: note("pin")) == "")
    #expect(NoteText.content(of: note("hello\nworld")) == "hello\nworld")
}

@Test func titleSkipsKeywordsAndMarkers() {
    #expect(NoteText.title(of: note("list\n\n- [ ] eggs\n- [ ] milk")) == "eggs")
    #expect(NoteText.title(of: note("pin")) == "empty note")
    #expect(NoteText.title(of: note(String(repeating: "a", count: 80))).count == 61)
}

@Test func customKeywords() {
    var keywords = Keywords.standard
    keywords.list = "todo"
    keywords.check = "done"
    #expect(NoteMode(text: "todo\n- [ ] a", keywords: keywords) == .list)
    #expect(NoteMode(text: "list\n- [ ] a", keywords: keywords) == .plain)
    #expect(Markers.strippingCheckKeyword("- [ ] call mom done", keyword: "done") == "- [ ] call mom")
    #expect(NoteText.content(of: note("todo\nx"), keywords: keywords) == "x")
}
