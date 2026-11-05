import Foundation

/// Makes sure a file exists so "Edit config file" always has something to open (PDR §8, 0.1.0).
///
/// Never truncates or rewrites an existing file.
public enum ConfigPlaceholder {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case createDirectory(path: String, reason: String)
        case createFile(path: String, errno: Int32)

        public var description: String {
            switch self {
            case let .createDirectory(path, reason):
                "Couldn't create \(path): \(reason)"
            case let .createFile(path, code):
                "Couldn't create \(path): \(String(cString: strerror(code)))"
            }
        }
    }

    /// Creates the parent directory and an empty file at `url` if missing.
    /// - Returns: `true` if the file was created, `false` if it already existed.
    @discardableResult
    public static func ensureExists(at url: URL) throws(Failure) -> Bool {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .createDirectory(path: directory.path, reason: error.localizedDescription)
        }

        // O_EXCL: atomic "create only if absent" — an existing file is left untouched.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        if fd >= 0 {
            close(fd)
            return true
        }
        if errno == EEXIST {
            return false
        }
        throw .createFile(path: url.path, errno: errno)
    }
}
