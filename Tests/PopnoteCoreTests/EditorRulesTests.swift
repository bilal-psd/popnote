import Testing
@testable import PopnoteCore

// MARK: Parsing

@Test func parsesMarkers() {
    #expect(Markers.parse("- [ ] milk").kind == .checkbox(checked: false))
    #expect(Markers.parse("- [x] milk").kind == .checkbox(checked: true))
    #expect(Markers.parse("- [X] milk").kind == .checkbox(checked: true))
    #expect(Markers.parse("- milk").kind == .bullet)
    #expect(Markers.parse("* milk").kind == .bullet)
    #expect(Markers.parse("12. milk").kind == .numbered(12))
    #expect(Markers.parse("milk").kind == .plain)
    #expect(Markers.parse("-milk").kind == .plain)
    #expect(Markers.parse("2024. was a year").kind == .plain)
}

@Test func parseKeepsIndentAndContent() {
    let parsed = Markers.parse("\t\t- [ ] eggs")
    #expect(parsed.indent == "\t\t")
    #expect(parsed.markerLength == 6)
    #expect(parsed.content == "eggs")
}

// MARK: Enter

@Test func enterContinuesLists() {
    #expect(Markers.newlineAction(for: "- [x] done", inListNote: false) == .continueWith("- [ ] "))
    #expect(Markers.newlineAction(for: "\t- item", inListNote: false) == .continueWith("\t- "))
    #expect(Markers.newlineAction(for: "3. third", inListNote: false) == .continueWith("4. "))
    #expect(Markers.newlineAction(for: "plain", inListNote: false) == .plain)
}

@Test func enterOnEmptyItemEndsList() {
    #expect(Markers.newlineAction(for: "- [ ] ", inListNote: false) == .endList)
    #expect(Markers.newlineAction(for: "\t- ", inListNote: true) == .endList)
}

@Test func listNotesAlwaysContinueWithCheckboxes() {
    #expect(Markers.newlineAction(for: "list", inListNote: true) == .continueWith("- [ ] "))
    #expect(Markers.newlineAction(for: "loose line", inListNote: true) == .continueWith("- [ ] "))
    #expect(Markers.newlineAction(for: "", inListNote: true) == .plain)
}

// MARK: Line commands

@Test func cycleGoesThroughAllKinds() {
    var line = "milk"
    line = Markers.cycled(line); #expect(line == "- [ ] milk")
    line = Markers.cycled(line); #expect(line == "- milk")
    line = Markers.cycled(line); #expect(line == "1. milk")
    line = Markers.cycled(line); #expect(line == "milk")
}

@Test func indentAndOutdent() {
    #expect(Markers.indented("- a") == "\t- a")
    #expect(Markers.outdented("\t- a") == "- a")
    #expect(Markers.outdented("      - a") == "  - a")
    #expect(Markers.outdented("- a") == "- a")
}

@Test func checkboxShortcut() {
    #expect(Markers.expandShortcut("[] ") == "- [ ] ")
    #expect(Markers.expandShortcut("\t[ ] ") == "\t- [ ] ")
    #expect(Markers.expandShortcut("a [] ") == nil)
}

@Test func checkKeyword() {
    #expect(Markers.strippingCheckKeyword("- [ ] call mom /x") == "- [ ] call mom")
    #expect(Markers.strippingCheckKeyword("- [ ] call mom/X") == "- [ ] call mom")
    #expect(Markers.strippingCheckKeyword("- [x] call mom /x") == nil)
    #expect(Markers.strippingCheckKeyword("call mom /x") == nil)
}

// MARK: Checking off

@Test func toggleKeepsItemInPlace() {
    let result = Checklist.toggle(lines: ["- [ ] a", "- [ ] b"], at: 0, behavior: .keep)
    #expect(result.lines == ["- [x] a", "- [ ] b"])
    #expect(result.index == 0)
}

@Test func checkedItemMovesToBottomOfItsList() {
    let lines = ["list", "- [ ] a", "- [ ] b", "- [x] c", "", "after"]
    let result = Checklist.toggle(lines: lines, at: 1, behavior: .moveToBottom)
    #expect(result.lines == ["list", "- [ ] b", "- [x] c", "- [x] a", "", "after"])
    #expect(result.index == 3)
}

@Test func checkedItemCanDeleteItself() {
    let result = Checklist.toggle(lines: ["- [ ] a", "- [ ] b"], at: 0, behavior: .delete)
    #expect(result.lines == ["- [ ] b"])
    #expect(result.index == nil)
}

@Test func uncheckingNeverMoves() {
    let result = Checklist.toggle(lines: ["- [x] a", "- [ ] b"], at: 0, behavior: .moveToBottom)
    #expect(result.lines == ["- [ ] a", "- [ ] b"])
}

// MARK: Paste

@Test func pasteStripsBulletsNumbersAndIndent() {
    let raw = "  • one\r\n\t2. two\n   - three\n3) four\nplain"
    #expect(PasteCleaner.clean(raw) == "one\ntwo\nthree\nfour\nplain")
}

@Test func pasteKeepsMarkdownCheckboxes() {
    #expect(PasteCleaner.clean("- [x] done\n- [ ] todo") == "- [x] done\n- [ ] todo")
}

@Test func pasteIntoListAddsMarkers() {
    let cleaned = PasteCleaner.clean("• eggs\n\n• milk\n", linePrefix: "- [ ] ", prefixFirstLine: true, dropEmptyLines: true)
    #expect(cleaned == "- [ ] eggs\n- [ ] milk")
}

@Test func pasteOntoExistingItemSkipsFirstPrefix() {
    let cleaned = PasteCleaner.clean("eggs\nmilk", linePrefix: "- ", prefixFirstLine: false)
    #expect(cleaned == "eggs\n- milk")
}

// MARK: Modes

@Test func noteModes() {
    #expect(NoteMode(text: "List\n- [ ] a") == .list)
    #expect(NoteMode(text: "code\nlet x = 1") == .code)
    #expect(NoteMode(text: "hello") == .plain)
}
