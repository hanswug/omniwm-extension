import Foundation

/// Maps tables and keys of a TOML document to their 1-based line numbers.
///
/// TOMLKit doesn't expose source positions for values, so validation errors
/// locate their line with this lightweight scan. It understands `[table]`,
/// `[[array]]` headers, bare and quoted keys, comments and multi-line strings.
/// Dotted keys and inline tables aren't resolved; lookups then return `nil`.
struct TOMLLineLocator {
    private struct Location: Hashable {
        var table: String
        var index: Int?
        var key: String?
    }

    private var lines: [Location: Int] = [:]

    init(_ text: String) {
        var table = ""
        var index: Int?
        var arrayCounts: [String: Int] = [:]
        var multilineDelimiter: String?

        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = raw.trimmingCharacters(in: .whitespaces)

            if let delimiter = multilineDelimiter {
                if line.contains(delimiter) { multilineDelimiter = nil }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[[") {
                guard let close = line.range(of: "]]") else { continue }
                let name = Self.unquote(String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound]))
                let next = (arrayCounts[name] ?? -1) + 1
                arrayCounts[name] = next
                (table, index) = (name, next)
                record(Location(table: name, index: next), lineNumber)
            } else if line.hasPrefix("[") {
                guard let close = line.firstIndex(of: "]") else { continue }
                let name = Self.unquote(String(line[line.index(after: line.startIndex)..<close]))
                (table, index) = (name, nil)
                record(Location(table: name, index: nil), lineNumber)
            } else if let equals = line.firstIndex(of: "=") {
                let key = Self.unquote(String(line[..<equals]))
                record(Location(table: table, index: index, key: key), lineNumber)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                for delimiter in ["\"\"\"", "'''"] where value.hasPrefix(delimiter) {
                    if !value.dropFirst(3).contains(delimiter) { multilineDelimiter = delimiter }
                }
            }
        }
    }

    private mutating func record(_ location: Location, _ line: Int) {
        if lines[location] == nil { lines[location] = line }
    }

    private static func unquote(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, let first = trimmed.first, first == "\"" || first == "'", trimmed.last == first {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// Line of `[table]` (or `""` for the root), or of `key` inside it.
    func line(table: String, key: String? = nil) -> Int? {
        lines[Location(table: table, index: nil, key: key)]
    }

    /// Line of the `index`-th (0-based) `[[table]]` header, or of `key` inside it.
    func line(arrayTable table: String, index: Int, key: String? = nil) -> Int? {
        lines[Location(table: table, index: index, key: key)]
    }
}
