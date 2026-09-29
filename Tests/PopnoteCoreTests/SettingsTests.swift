import Foundation
import Testing
@testable import PopnoteCore

@Test func legacyKeywordsUntilRemoved() {
    let defaults = UserDefaults.standard
    let keys = Settings.Key.legacyKeywords + [Settings.Key.keywordsRemoved]
    keys.forEach(defaults.removeObject(forKey:))
    defer { keys.forEach(defaults.removeObject(forKey:)) }

    #expect(Settings.legacyKeywords?.pin == "pin")
    #expect(Settings.legacyKeywords?.all == ["list", "code", "pin"])

    defaults.set(" Keep ", forKey: "keywordPin")
    defaults.set("", forKey: "keywordList")
    #expect(Settings.legacyKeywords?.pin == "keep")
    #expect(Settings.legacyKeywords?.all == ["list", "code", "keep"])

    Settings.removeKeywords()
    #expect(Settings.legacyKeywords == nil)
    #expect(defaults.object(forKey: "keywordPin") == nil)
}
