import Foundation
import Testing
@testable import PopnoteCore

private func note(_ body: String) -> Note {
    Note(id: 1, body: body, createdAt: Date(), updatedAt: Date())
}

@Test func keywordLineIsDroppedOnExport() {
    #expect(Exporter.content(of: note("list\n- [ ] eggs")) == "- [ ] eggs")
    #expect(Exporter.content(of: note("pin")) == "")
    #expect(Exporter.content(of: note("hello\nworld")) == "hello\nworld")
}

@Test func titleSkipsKeywordsAndMarkers() {
    #expect(Exporter.title(of: note("list\n\n- [ ] eggs\n- [ ] milk")) == "eggs")
    #expect(Exporter.title(of: note("pin")) == "Popnote note")
    #expect(Exporter.title(of: note(String(repeating: "a", count: 80))).count == 61)
}

@Test func fileNameHasNoSlashes() {
    #expect(Exporter.fileName(of: note("a/b: c?")) == "a-b- c-")
}

@Test func markdownFencesCode() {
    #expect(Exporter.markdown(of: note("code\nlet x = 1")) == "```\nlet x = 1\n```")
    #expect(Exporter.markdown(of: note("- [x] done")) == "- [x] done")
}

@Test func appleNotesHTML() {
    let html = Exporter.notesHTML(of: note("list\n- [ ] a & b\n\t- [x] <c>\n\n2. two"))
    #expect(html == "<div>☐ a &amp; b</div><div>\u{00A0}\u{00A0}\u{00A0}\u{00A0}☑ &lt;c&gt;</div><div><br></div><div>2. two</div>")
}

@Test func urlsEncodeEverything() {
    let url = Exporter.obsidianURL(for: note("a & b = c+d"), vault: "My Vault")!
    #expect(url.absoluteString == "obsidian://new?vault=My%20Vault&name=a%20%26%20b%20%3D%20c%2Bd&content=a%20%26%20b%20%3D%20c%2Bd")
    #expect(Exporter.bearURL(for: note("hi"))!.absoluteString == "bear://x-callback-url/create?text=hi")
}

@Test func customKeywords() {
    var keywords = Keywords.standard
    keywords.list = "todo"
    keywords.check = "done"
    #expect(NoteMode(text: "todo\n- [ ] a", keywords: keywords) == .list)
    #expect(NoteMode(text: "list\n- [ ] a", keywords: keywords) == .plain)
    #expect(Markers.strippingCheckKeyword("- [ ] call mom done", keyword: "done") == "- [ ] call mom")
    #expect(Exporter.content(of: note("todo\nx"), keywords: keywords) == "x")
}
