import Foundation
import Testing
@testable import PopnoteCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func note(_ id: Int64, _ body: String, editedAgo minutes: Double, pinned: Bool = false) -> Note {
    Note(id: id, body: body, createdAt: t0.addingTimeInterval(-86400), updatedAt: t0.addingTimeInterval(-minutes * 60), pinned: pinned)
}

@Test func pinnedFirstThenMostRecent() {
    let notes = [
        note(1, "old", editedAgo: 300),
        note(2, "pinned old", editedAgo: 900, pinned: true),
        note(3, "fresh", editedAgo: 1),
        note(4, "pin\nkeyword pinned", editedAgo: 5),
    ]
    let sections = Browse.sections(notes)
    #expect(sections.pinned.map(\.id) == [4, 2])
    #expect(sections.recent.map(\.id) == [3, 1])
}

@Test func filterMatchesBodyIgnoringCase() {
    let notes = [note(1, "Deploy notes", editedAgo: 1), note(2, "groceries", editedAgo: 2)]
    #expect(Browse.sections(notes, filter: "deploy").recent.map(\.id) == [1])
    #expect(Browse.sections(notes, filter: "  ").recent.count == 2)
}

@Test func ageLabels() {
    #expect(Browse.age(of: note(1, "", editedAgo: 0.5), now: t0) == "now")
    #expect(Browse.age(of: note(1, "", editedAgo: 5), now: t0) == "5m")
    #expect(Browse.age(of: note(1, "", editedAgo: 150), now: t0) == "2h")
    #expect(Browse.age(of: note(1, "", editedAgo: 60 * 24 * 3), now: t0) == "3d")
}
