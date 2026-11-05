import Foundation

/// Reading and first-launch creation of `config.toml` (PDR §4).
public enum ConfigFile {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case createDirectory(path: String, reason: String)
        case write(path: String, reason: String)

        public var description: String {
            switch self {
            case let .createDirectory(path, reason): "Couldn't create \(path): \(reason)"
            case let .write(path, reason): "Couldn't write \(path): \(reason)"
            }
        }
    }

    /// Writes the commented default config if the file is missing or blank,
    /// creating the directory as needed. A file with any content is never touched.
    ///
    /// Blank counts as missing because 0.1.0 created an empty placeholder.
    /// - Returns: `true` if the default was written.
    @discardableResult
    public static func writeDefaultIfMissing(at url: URL) throws(Failure) -> Bool {
        if let data = try? Data(contentsOf: url),
           !String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) {
            return false
        }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .createDirectory(path: directory.path, reason: error.localizedDescription)
        }
        do {
            try Data(ExtConfig.defaultFileContents.utf8).write(to: url, options: .atomic)
        } catch {
            throw .write(path: url.path, reason: error.localizedDescription)
        }
        return true
    }

    /// Reads the file for `ConfigStore.apply(_:)`.
    public static func load(from url: URL) -> ConfigStore.Load {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .failed(ConfigIssue(.error, "\(url.path) not found"))
        } catch {
            return .failed(ConfigIssue(.error, "couldn't read \(url.path): \(error.localizedDescription)"))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failed(ConfigIssue(.error, "\(url.lastPathComponent) is not valid UTF-8"))
        }
        return .read(text: text)
    }
}
