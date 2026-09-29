import Foundation

/// Fuzzy matching for the command palette: the query's characters must
/// appear in order. Higher scores are better matches.
public enum Fuzzy {
    public static func score(_ query: String, in text: String) -> Int? {
        let query = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !query.isEmpty else { return 0 }
        let text = Array(text.lowercased())
        var score = 0
        var q = 0
        var previousMatch = -2
        for (i, char) in text.enumerated() where q < query.count && char == query[q] {
            score += 1
            if i == previousMatch + 1 { score += 3 }                     // consecutive letters
            if i == 0 || !text[i - 1].isLetter { score += 5 }             // start of a word
            previousMatch = i
            q += 1
        }
        guard q == query.count else { return nil }
        return score - text.count / 10 // prefer shorter titles on ties
    }

    /// Items matching `query`, best first. Ties keep their original order.
    public static func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        items.enumerated()
            .compactMap { offset, item in score(query, in: text(item)).map { (item, $0, offset) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}
