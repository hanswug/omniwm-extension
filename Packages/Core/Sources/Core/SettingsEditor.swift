import Foundation

/// A scalar value written into OmniWM's `settings.toml` (PDR §6.1 rule 4).
public enum TOMLScalar: Sendable, Equatable, CustomStringConvertible {
    case float(Double)
    case int(Int)
    case bool(Bool)

    /// OmniWM's style: floats always carry a decimal point (`540.0`), integers don't (`3`).
    public var description: String {
        switch self {
        case let .float(value):
            if value == value.rounded(), abs(value) < 1e15 { return "\(Int64(value)).0" }
            return "\(value)"
        case let .int(value): return "\(value)"
        case let .bool(value): return value ? "true" : "false"
        }
    }

    /// Whether an existing value token already holds this value (`540` == `540.0`).
    func matches(token: Substring) -> Bool {
        switch self {
        case let .bool(value):
            return token == (value ? "true" : "false")
        case let .float(value):
            return Self.number(token).map { $0 == value } ?? false
        case let .int(value):
            return Self.number(token).map { $0 == Double(value) } ?? false
        }
    }

    private static func number(_ token: Substring) -> Double? {
        Double(token.replacingOccurrences(of: "_", with: ""))
    }
}

/// One key to set: `[table] key = value`.
public struct SettingsEdit: Sendable, Equatable {
    public let table: String
    public let key: String
    public let value: TOMLScalar

    public init(table: String, key: String, value: TOMLScalar) {
        self.table = table
        self.key = key
        self.value = value
    }
}

public enum SettingsEditError: Error, Sendable, Equatable, CustomStringConvertible {
    case tableNotFound(String)
    case unexpectedValue(table: String, key: String)
    case invalidValue(String)
    case notUTF8
    case io(operation: String, path: String, errno: Int32)
    case concurrentModification
    /// A command needed to read a value that isn't there (e.g. `[borders] enabled` to toggle it).
    case keyNotFound(table: String, key: String)
    /// The file isn't valid TOML; we don't edit what OmniWM itself couldn't load.
    case unparseable(String)

    public var description: String {
        switch self {
        case let .keyNotFound(table, key): "[\(table)] \(key) not found in OmniWM settings"
        case let .unparseable(reason): "OmniWM settings can't be parsed: \(reason)"
        case let .tableNotFound(table): "table [\(table)] not found in OmniWM settings"
        case let .unexpectedValue(table, key): "[\(table)] \(key) has a non-scalar value; not touching it"
        case let .invalidValue(value): "can't write value \(value)"
        case .notUTF8: "OmniWM settings are not valid UTF-8"
        case let .io(operation, path, code): "\(operation) \(path) failed: \(String(cString: strerror(code)))"
        case .concurrentModification: "OmniWM settings kept changing while saving; gave up after one retry"
        }
    }
}

public enum SettingsEditOutcome: Sendable, Equatable {
    case written
    /// Every value already matched; the file was not touched (PDR §6.1 rule 8).
    case unchanged
}

/// Surgical, atomic edits of OmniWM's `settings.toml` (PDR §6.1).
///
/// Only the value token of each target line changes; every other byte stays
/// identical, including indentation, spacing, trailing comments and line endings.
public enum SettingsEditor {
    // MARK: - File

    /// Applies `edits` to the file at `url`: fresh read, atomic write via rename,
    /// permissions preserved, one retry if the file changed underneath us.
    /// Symlinks are followed, so a symlinked `settings.toml` stays a symlink.
    @discardableResult
    public static func edit(fileAt url: URL, _ edits: [SettingsEdit]) throws(SettingsEditError) -> SettingsEditOutcome {
        try edit(fileAt: url, computing: { _ throws(SettingsEditError) in edits }, beforeRename: { _ in })
    }

    /// Like `edit(fileAt:_:)`, but the edits are computed from the freshly read text
    /// on every attempt, so a retry after a concurrent change re-decides (e.g. cycling).
    @discardableResult
    public static func edit(
        fileAt url: URL, computing: (String) throws(SettingsEditError) -> [SettingsEdit]
    ) throws(SettingsEditError) -> SettingsEditOutcome {
        try edit(fileAt: url, computing: computing, beforeRename: { _ in })
    }

    /// Test seam: `beforeRename(attempt)` runs after the temp file is written, before the guard check.
    static func edit(
        fileAt url: URL, _ edits: [SettingsEdit], beforeRename: (Int) -> Void
    ) throws(SettingsEditError) -> SettingsEditOutcome {
        try edit(fileAt: url, computing: { _ throws(SettingsEditError) in edits }, beforeRename: beforeRename)
    }

    static func edit(
        fileAt url: URL, computing: (String) throws(SettingsEditError) -> [SettingsEdit], beforeRename: (Int) -> Void
    ) throws(SettingsEditError) -> SettingsEditOutcome {
        let target = url.resolvingSymlinksInPath()
        for attempt in 0..<2 {
            let snapshot = try FileSnapshot.read(target)
            guard let text = String(data: snapshot.data, encoding: .utf8) else { throw .notUTF8 }
            let updated = try apply(try computing(text), to: text)
            if updated == text { return .unchanged }

            let temp = try writeTemp(Data(updated.utf8), nextTo: target, mode: snapshot.identity.mode)
            beforeRename(attempt)

            // Lost-update guard: the file must still be exactly what we read.
            guard (try? FileSnapshot.identity(of: target)) == snapshot.identity else {
                unlink(temp.path)
                continue
            }
            guard rename(temp.path, target.path) == 0 else {
                let code = errno
                unlink(temp.path)
                throw .io(operation: "rename", path: target.path, errno: code)
            }
            return .written
        }
        throw .concurrentModification
    }

    // MARK: - Text

    /// Pure text transform behind `edit(fileAt:_:)`.
    public static func apply(_ edits: [SettingsEdit], to text: String) throws(SettingsEditError) -> String {
        // components(separatedBy:) splits on the "\n" code unit, so "\r\n" (one Swift Character) keeps its "\r".
        var lines = text.components(separatedBy: "\n")
        for edit in edits {
            try apply(edit, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func apply(_ edit: SettingsEdit, to lines: inout [String]) throws(SettingsEditError) {
        if case let .float(value) = edit.value, !value.isFinite { throw .invalidValue("\(value)") }

        guard let header = lines.firstIndex(where: { headerName(of: $0) == edit.table }) else {
            throw .tableNotFound(edit.table)
        }
        // The body runs until the next line starting with `[` or EOF (rule 2).
        var end = header + 1
        while end < lines.count, !lines[end].drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("[") {
            end += 1
        }

        for index in (header + 1)..<end {
            guard let parts = KeyLine(lines[index]), parts.key == edit.key else { continue }
            if let first = parts.value.first, "\"'[{".contains(first) {
                throw .unexpectedValue(table: edit.table, key: edit.key)
            }
            if edit.value.matches(token: parts.value) { return } // idempotent
            lines[index] = parts.prefix + edit.value.description + parts.suffix
            return
        }

        // Missing key: insert as the first body line (rule 3), matching the header's line ending.
        let lineEnding = lines[header].hasSuffix("\r") ? "\r" : ""
        lines.insert("\(edit.key) = \(edit.value)\(lineEnding)", at: header + 1)
    }

    /// `[name]` → `name` (whitespace and a trailing comment allowed). `nil` for anything else, incl. `[[array]]`.
    private static func headerName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\r")))
        guard trimmed.hasPrefix("["), !trimmed.hasPrefix("[["), let close = trimmed.firstIndex(of: "]") else { return nil }
        let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || rest.hasPrefix("#") else { return nil }
        return trimmed[trimmed.index(after: trimmed.startIndex)..<close].trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Atomic write

    private static func writeTemp(_ data: Data, nextTo target: URL, mode: mode_t) throws(SettingsEditError) -> URL {
        let directory = target.deletingLastPathComponent()
        var template = Array(directory.appending(path: ".\(target.lastPathComponent).omniwm-extension.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw .io(operation: "create temp file in", path: directory.path, errno: errno) }
        let path = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let temp = URL(filePath: path)

        func fail(_ operation: String) -> SettingsEditError {
            let code = errno
            close(fd)
            unlink(temp.path)
            return .io(operation: operation, path: temp.path, errno: code)
        }

        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = write(fd, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
        guard written else { throw fail("write") }
        guard fchmod(fd, mode & 0o7777) == 0 else { throw fail("chmod") }
        guard fsync(fd) == 0 else { throw fail("fsync") }
        close(fd)
        return temp
    }
}

/// `<indent><key><ws>=<ws>` + `<value token>` + `<rest: ws, comment, \r>`.
private struct KeyLine {
    let prefix: String
    let key: String
    let value: Substring
    let suffix: String

    init?(_ line: String) {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let rawKey = line[..<equals].trimmingCharacters(in: .whitespaces)
        if rawKey.count >= 2, let quote = rawKey.first, quote == "\"" || quote == "'", rawKey.last == quote {
            key = String(rawKey.dropFirst().dropLast())
        } else {
            guard !rawKey.isEmpty, rawKey.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
            key = rawKey
        }
        let afterEquals = line[line.index(after: equals)...]
        let valueStart = afterEquals.firstIndex(where: { $0 != " " && $0 != "\t" }) ?? afterEquals.endIndex
        let valueEnd = line[valueStart...].firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "#" || $0 == "\r" }) ?? line.endIndex
        prefix = String(line[..<valueStart])
        value = line[valueStart..<valueEnd]
        suffix = String(line[valueEnd...])
        if value.isEmpty { return nil }
    }
}

/// Bytes plus the identity used by the lost-update guard (mtime + size, and inode/device).
private struct FileSnapshot {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let mtimeSeconds: Int
        let mtimeNanoseconds: Int
        let mode: mode_t
    }

    let data: Data
    let identity: Identity

    static func read(_ url: URL) throws(SettingsEditError) -> FileSnapshot {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw .io(operation: "open", path: url.path, errno: errno) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw .io(operation: "stat", path: url.path, errno: errno) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw .io(operation: "read", path: url.path, errno: errno)
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return FileSnapshot(data: data, identity: Identity(info))
    }

    static func identity(of url: URL) throws(SettingsEditError) -> Identity {
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw .io(operation: "stat", path: url.path, errno: errno) }
        return Identity(info)
    }
}

private extension FileSnapshot.Identity {
    init(_ info: stat) {
        self.init(
            device: info.st_dev, inode: info.st_ino, size: info.st_size,
            mtimeSeconds: info.st_mtimespec.tv_sec, mtimeNanoseconds: info.st_mtimespec.tv_nsec,
            mode: info.st_mode
        )
    }
}
