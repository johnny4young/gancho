import Testing

@testable import GanchoAppCore

@Suite("Screen OCR authorization outcomes")
struct ScreenTextAuthorizationTests {
    @Test("Existing authorization skips both explanation and OS request")
    func alreadyAuthorized() {
        var calls: [String] = []
        let result = ScreenTextAuthorization.resolve(
            isAuthorized: {
                calls.append("preflight")
                return true
            },
            confirmPurpose: {
                calls.append("purpose")
                return true
            },
            requestAccess: {
                calls.append("request")
                return true
            })
        #expect(result == .allowed)
        #expect(calls == ["preflight"])
    }

    @Test("Cancelling the explanation is distinct from denial and never requests access")
    func cancelPurpose() {
        var calls: [String] = []
        let result = ScreenTextAuthorization.resolve(
            isAuthorized: {
                calls.append("preflight")
                return false
            },
            confirmPurpose: {
                calls.append("purpose")
                return false
            },
            requestAccess: {
                calls.append("request")
                return true
            })
        #expect(result == .cancelled)
        #expect(calls == ["preflight", "purpose"])
    }

    @Test(
        "Only confirmed explanations request access, preserving the OS outcome",
        arguments: [true, false])
    func requestAfterConfirmation(granted: Bool) {
        var calls: [String] = []
        let result = ScreenTextAuthorization.resolve(
            isAuthorized: {
                calls.append("preflight")
                return false
            },
            confirmPurpose: {
                calls.append("purpose")
                return true
            },
            requestAccess: {
                calls.append("request")
                return granted
            })
        #expect(result == (granted ? .allowed : .denied))
        #expect(calls == ["preflight", "purpose", "request"])
    }

    @Test("Each invocation rechecks access rather than caching grants or denials")
    func changedAuthorization() {
        var authorized = true
        var requests = 0
        func resolve() -> ScreenTextAuthorization {
            ScreenTextAuthorization.resolve(
                isAuthorized: { authorized }, confirmPurpose: { true },
                requestAccess: {
                    requests += 1
                    return false
                })
        }
        #expect(resolve() == .allowed)
        authorized = false
        #expect(resolve() == .denied)
        authorized = true
        #expect(resolve() == .allowed)
        #expect(requests == 1)
    }
}
