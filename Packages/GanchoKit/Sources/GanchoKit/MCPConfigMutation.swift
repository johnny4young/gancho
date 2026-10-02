import Darwin
import Foundation

public enum MCPConfigMutationError: Error, Equatable { case busy, unsupportedVersion }

extension MCPServerConfig {
    /// Reads, mutates and publishes one policy while holding an interprocess lock.
    /// Contention fails explicitly rather than blocking the app actor.
    /// Unlike a cached snapshot save, this cannot restore an already revoked grant.
    @discardableResult
    public static func update(
        in directory: URL, _ mutate: (inout MCPServerConfig) throws -> Void
    ) throws -> MCPServerConfig {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(".mcp-config.lock")
        let descriptor = lockURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        }
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw MCPConfigMutationError.busy }
            throw CocoaError(.fileWriteUnknown)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        let url = directory.appendingPathComponent(fileName)
        var config = MCPServerConfig()
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let header = try JSONDecoder().decode(MCPConfigurationHeader.self, from: data)
            guard (1...currentSchemaVersion).contains(header.schemaVersion ?? 1) else {
                throw MCPConfigMutationError.unsupportedVersion
            }
            config = try JSONDecoder().decode(Self.self, from: data)
        }
        try mutate(&config)
        try config.save(toStoreDirectory: directory)
        return config
    }
}

private struct MCPConfigurationHeader: Decodable { let schemaVersion: Int? }
