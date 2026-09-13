/// Permission orchestration without platform APIs. Cancelling the purpose
/// explanation is not an OS denial and must never request screen access.
public enum ScreenTextAuthorization: Sendable, Equatable {
    case allowed, denied, cancelled

    public static func resolve(
        isAuthorized: () -> Bool,
        confirmPurpose: () -> Bool,
        requestAccess: () -> Bool
    ) -> Self {
        if isAuthorized() { return .allowed }
        guard confirmPurpose() else { return .cancelled }
        return requestAccess() ? .allowed : .denied
    }
}
