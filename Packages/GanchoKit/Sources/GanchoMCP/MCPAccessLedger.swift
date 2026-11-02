import GanchoKit

/// The runner log `gancho mcp` uses: write the ledger row, then signal the
/// app. A failed write signals nothing, so the app never looks for a row
/// that is not there.
public enum MCPAccessLedger {
    public static func log(
        record: @escaping @Sendable (MCPAccessEvent) async throws -> Void,
        signal: @escaping @Sendable () -> Void
    ) -> @Sendable (MCPAccessEvent) async -> Void {
        { event in
            guard (try? await record(event)) != nil else { return }
            signal()
        }
    }
}
