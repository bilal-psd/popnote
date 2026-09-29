import Foundation
import Testing
@testable import PopnoteCore

private let day: TimeInterval = 86400
private let ttl = 3 * day
private let retention = 7 * day
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func unpinnedNoteExpiresAfterTTL() throws {
    let store = try NoteStore(url: nil)
    let note = try store.insert(body: "buy milk", now: t0)

    try store.sweep(now: t0.addingTimeInterval(ttl - 60), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().map(\.id) == [note.id])

    try store.sweep(now: t0.addingTimeInterval(ttl), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().isEmpty)
    #expect(try store.trashedNotes().map(\.id) == [note.id])
}

@Test func editingRestartsTheClock() throws {
    let store = try NoteStore(url: nil)
    let note = try store.insert(body: "a", now: t0)
    try store.updateBody(id: note.id, body: "ab", now: t0.addingTimeInterval(2 * day))

    try store.sweep(now: t0.addingTimeInterval(4 * day), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().count == 1)
}

@Test func pinnedNotesNeverExpire() throws {
    let store = try NoteStore(url: nil)
    let flagged = try store.insert(body: "keep me", now: t0)
    try store.setPinned(id: flagged.id, true)
    try store.insert(body: "pin\nwifi password", now: t0)

    try store.sweep(now: t0.addingTimeInterval(365 * day), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().count == 2)
}

@Test func unpinnedNoteKeepsItsOriginalClock() throws {
    let store = try NoteStore(url: nil)
    let note = try store.insert(body: "x", now: t0)
    try store.setPinned(id: note.id, true)
    try store.setPinned(id: note.id, false)

    try store.sweep(now: t0.addingTimeInterval(ttl), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().isEmpty)
}

@Test func blankExpiredNotesSkipTrash() throws {
    let store = try NoteStore(url: nil)
    try store.insert(body: "  \n ", now: t0)

    try store.sweep(now: t0.addingTimeInterval(ttl), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().isEmpty)
    #expect(try store.trashedNotes().isEmpty)
}

@Test func trashIsPurgedAfterRetention() throws {
    let store = try NoteStore(url: nil)
    let note = try store.insert(body: "old", now: t0)
    try store.moveToTrash(id: note.id, now: t0)

    try store.sweep(now: t0.addingTimeInterval(retention - 60), ttl: ttl, trashRetention: retention)
    #expect(try store.trashedNotes().count == 1)

    try store.sweep(now: t0.addingTimeInterval(retention), ttl: ttl, trashRetention: retention)
    #expect(try store.trashedNotes().isEmpty)
    #expect(try store.note(id: note.id) == nil)
}

@Test func restoredNoteGetsAFreshClock() throws {
    let store = try NoteStore(url: nil)
    let note = try store.insert(body: "oops", now: t0)
    try store.sweep(now: t0.addingTimeInterval(ttl), ttl: ttl, trashRetention: retention)

    let later = t0.addingTimeInterval(ttl + day)
    try store.restore(id: note.id, now: later)
    try store.sweep(now: later.addingTimeInterval(day), ttl: ttl, trashRetention: retention)
    #expect(try store.activeNotes().map(\.id) == [note.id])
}

@Test func activeNotesAreOldestFirst() throws {
    let store = try NoteStore(url: nil)
    let a = try store.insert(body: "a", now: t0)
    let b = try store.insert(body: "b", now: t0.addingTimeInterval(1))
    #expect(try store.activeNotes().map(\.id) == [a.id, b.id])
}

@Test func keywordIsFirstLineOnly() {
    let note = Note(id: 1, body: "  PIN \nsomething", createdAt: t0, updatedAt: t0)
    #expect(note.keyword == "pin")
    #expect(note.isPinned)
    let other = Note(id: 2, body: "hello\npin", createdAt: t0, updatedAt: t0)
    #expect(!other.isPinned)
}

