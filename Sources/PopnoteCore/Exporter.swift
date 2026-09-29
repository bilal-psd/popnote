import Foundation

/// Turns a note into what other apps and files expect. The keyword line
/// ("list", "code", "pin") is Popnote-only, so it's dropped.
public enum Exporter {
    /// The note's text without its keyword line.
    public static func content(of note: Note, keywords: Keywords = .current) -> String {
        guard let keyword = note.keyword, keywords.firstLine.contains(keyword) else { return note.body }
        let rest = note.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
        return String(rest ?? "")
    }

    /// First non-empty line without list markers, cut to 60 characters.
    public static func title(of note: Note, keywords: Keywords = .current) -> String {
        let line = content(of: note, keywords: keywords)
            .split(separator: "\n")
            .map { Markers.parse(String($0)).content.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        let title = line.count > 60 ? String(line.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" : line
        return title.isEmpty ? "Popnote note" : title
    }

    /// The title with characters that aren't allowed in file names replaced.
    public static func fileName(of note: Note, keywords: Keywords = .current) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        return title(of: note, keywords: keywords).components(separatedBy: forbidden).joined(separator: "-")
    }

    public static func plainText(of note: Note, keywords: Keywords = .current) -> String {
        content(of: note, keywords: keywords)
    }

    /// Markdown. Checkboxes and bullets are already Markdown; code notes get fenced.
    public static func markdown(of note: Note, keywords: Keywords = .current) -> String {
        let text = content(of: note, keywords: keywords)
        return NoteMode(text: note.body, keywords: keywords) == .code ? "```\n\(text)\n```" : text
    }

    /// HTML for Apple Notes, which has no Markdown. Checkboxes become ☐/☑ and
    /// bullets become •, with indentation kept as spaces.
    public static func notesHTML(of note: Note, keywords: Keywords = .current) -> String {
        let isCode = NoteMode(text: note.body, keywords: keywords) == .code
        let lines = content(of: note, keywords: keywords).components(separatedBy: "\n").map { line -> String in
            var rendered = line
            if !isCode {
                let parsed = Markers.parse(line)
                let indent = String(repeating: "\u{00A0}", count: parsed.indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) })
                switch parsed.kind {
                case .checkbox(let checked): rendered = indent + (checked ? "☑ " : "☐ ") + parsed.content
                case .bullet: rendered = indent + "• " + parsed.content
                case .numbered, .plain: rendered = indent + parsed.markerPrefix(in: line) + parsed.content
                }
            }
            let escaped = escapeHTML(rendered)
            return "<div>\(escaped.isEmpty ? "<br>" : escaped)</div>"
        }
        let body = lines.joined()
        return isCode ? "<pre>\(body)</pre>" : body
    }

    /// obsidian://new — creates a note in `vault`, or the vault that's open.
    public static func obsidianURL(for note: Note, vault: String?, keywords: Keywords = .current) -> URL? {
        var params = [("name", fileName(of: note, keywords: keywords)), ("content", markdown(of: note, keywords: keywords))]
        if let vault { params.insert(("vault", vault), at: 0) }
        return URL(string: "obsidian://new?" + query(params))
    }

    /// bear://x-callback-url/create
    public static func bearURL(for note: Note, keywords: Keywords = .current) -> URL? {
        URL(string: "bear://x-callback-url/create?" + query([("text", markdown(of: note, keywords: keywords))]))
    }

    // MARK: Helpers

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Strict encoding: URLComponents leaves "&", "=" and "+" alone in values,
    /// which breaks notes containing them.
    private static func query(_ params: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }
}

private extension ParsedLine {
    /// The original marker text ("3. "), or "" for plain lines.
    func markerPrefix(in line: String) -> String {
        String(line.dropFirst(indent.count).prefix(markerLength))
    }
}
