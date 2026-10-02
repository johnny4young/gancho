import Darwin
import Foundation
import Testing

@testable import GanchoKit

@Suite("MCP policy mutations")
struct MCPConfigMutationTests {
    @Test func concurrentAppendsAndRevocationCannotOverwriteEachOther() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = MCPClientGrant(clientName: "Original")
        try MCPServerConfig(isEnabled: true, grants: [original]).save(toStoreDirectory: directory)
        let saved = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<20 {
                group.addTask {
                    do {
                        try MCPServerConfig.update(in: directory) {
                            $0.grants.append(MCPClientGrant(clientName: "Synthetic \(index)"))
                        }
                        return true
                    } catch MCPConfigMutationError.busy { return false }
                }
            }
            var saved = 0
            for try await success in group where success { saved += 1 }
            return saved
        }
        try MCPServerConfig.update(in: directory) { $0.grants[0].revokedAt = .now }
        try MCPServerConfig.update(in: directory) {
            $0.grants.append(MCPClientGrant(clientName: "After revocation"))
        }
        let final = MCPServerConfig.load(fromStoreDirectory: directory)
        #expect(saved > 0)
        #expect(final.grants.count == saved + 2)
        #expect(final.grants[0].revokedAt != nil)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(".mcp-config.lock").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func heldPolicyLockFailsPromptlyWithoutChangingAuthorization() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try MCPServerConfig().save(toStoreDirectory: directory)
        let path = directory.appendingPathComponent(".mcp-config.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        defer { _ = flock(descriptor, LOCK_UN) }
        #expect(throws: MCPConfigMutationError.busy) {
            try MCPServerConfig.update(in: directory) { $0.isEnabled = true }
        }
        #expect(!MCPServerConfig.load(fromStoreDirectory: directory).isEnabled)
    }

    @Test func corruptConfigurationAndFailedMutationLeaveBytesUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(MCPServerConfig.fileName)
        let corrupt = Data("invalid synthetic policy".utf8)
        try corrupt.write(to: url)
        #expect(throws: (any Error).self) {
            try MCPServerConfig.update(in: directory) { $0.isEnabled = true }
        }
        #expect(try Data(contentsOf: url) == corrupt)
        let future = Data(#"{"schemaVersion":999,"isEnabled":false,"grants":[]}"#.utf8)
        try future.write(to: url)
        #expect(throws: MCPConfigMutationError.unsupportedVersion) {
            try MCPServerConfig.update(in: directory) { $0.isEnabled = true }
        }
        #expect(try Data(contentsOf: url) == future)
        try MCPServerConfig().save(toStoreDirectory: directory)
        let before = try Data(contentsOf: url)
        #expect(throws: CancellationError.self) {
            try MCPServerConfig.update(in: directory) { config in
                config.isEnabled = true
                throw CancellationError()
            }
        }
        #expect(try Data(contentsOf: url) == before)
    }
}
