import Foundation
import Testing

@testable import GanchoKit

@Suite("MCP access scope — elevation surface")
struct MCPAccessScopeTests {
    @Test("metadata scope is not elevated; content-exposing scopes are")
    func elevationTracksContentExposure() {
        #expect(MCPServerConfig(isEnabled: true, scope: .metadata).isElevated == false)
        #expect(MCPServerConfig(isEnabled: true, scope: .boards).isElevated == true)
        #expect(MCPServerConfig(isEnabled: true, scope: .all).isElevated == true)
    }

    @Test("the default (opt-in-by-absence) config is not elevated")
    func defaultConfigIsNotElevated() {
        #expect(MCPServerConfig().isElevated == false)
    }
}
