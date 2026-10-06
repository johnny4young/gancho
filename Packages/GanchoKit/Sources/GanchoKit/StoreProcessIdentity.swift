import Darwin
import Foundation
import GRDB

/// Reuse-proof identity for ownership claims, and the ledger schema that
/// stores it. A PID alone cannot prove a claim stale: PIDs restart at every
/// boot and wrap within one, so a jetsam-killed claimant's PID can belong to an
/// unrelated live process. The boot session and process start time can.
extension StoreProcessOwnership {
    /// How the current process judges another claim's liveness.
    struct Liveness: Sendable {
        /// This boot's `kern.bootsessionuuid`; empty when unavailable.
        var bootSession: String
        /// Start time of a live PID, microseconds since 1970; nil when unknown.
        var startTime: @Sendable (Int32) -> Int64?

        static var system: Self {
            Self(bootSession: currentBootSession, startTime: processStartTime)
        }
    }

    static let currentBootSession: String = readBootSession()
    static let currentStartTime: Int64 = processStartTime(getpid()) ?? 0

    static let ownerQuery = """
        SELECT o.token AS token, o.processToken AS processToken, o.pid AS pid,
               o.scope AS scope, o.exclusive AS exclusive,
               i.bootSession AS bootSession, i.startTime AS startTime
        FROM owner o LEFT JOIN owner_identity i ON i.token = o.token
        """

    /// Fail-closed staleness. Only positive evidence removes a claim:
    /// - a different boot session (claims never survive a reboot), or
    /// - `ESRCH` for the PID, or
    /// - a PID this process may signal whose start time differs from the one
    ///   recorded with the claim (the PID was reused).
    /// Unknown stamps (version-1 claims, unavailable sysctls) and processes that
    /// cannot be inspected keep their claim.
    static func isStale(
        _ claim: Identity, probe: (Int32) -> ProcessState, liveness: Liveness
    ) -> Bool {
        if !claim.bootSession.isEmpty, !liveness.bootSession.isEmpty,
            claim.bootSession != liveness.bootSession
        {
            return true
        }
        switch probe(claim.pid) {
        case .exited: return true
        case .unverifiable: return false
        case .live:
            guard claim.startTime > 0, let observed = liveness.startTime(claim.pid) else {
                return false
            }
            return observed != claim.startTime
        }
    }

    /// Identity rows only have meaning beside their claim; both are written in
    /// one transaction, so an unmatched one is a released claim's remainder.
    static func removeOrphanIdentities(in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM owner_identity WHERE token NOT IN (SELECT token FROM owner)")
    }

    static let ownerSchema = """
        CREATE TABLE owner (
            token TEXT PRIMARY KEY NOT NULL,
            processToken TEXT NOT NULL,
            pid INTEGER NOT NULL CHECK (pid > 0 AND pid <= 2147483647),
            scope TEXT NOT NULL CHECK (scope IN ('generation', 'blob')),
            exclusive INTEGER NOT NULL CHECK (exclusive IN (0, 1))
        )
        """

    static let identitySchema = """
        CREATE TABLE owner_identity (
            token TEXT PRIMARY KEY NOT NULL,
            bootSession TEXT NOT NULL,
            startTime INTEGER NOT NULL CHECK (startTime >= 0)
        )
        """

    /// Version 1 held only `owner`. Version 2 adds `owner_identity`; version-1
    /// claims stay valid and are judged by their PID alone. A missing, unknown
    /// or altered ledger is never recreated: that could erase knowledge of an
    /// active logical owner.
    static func prepareSchema(_ db: Database) throws {
        let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        let owner = try tableSQL("owner", in: db)
        let identity = try tableSQL("owner_identity", in: db)
        switch version {
        case 0:
            let query = "SELECT COUNT(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
            let objects = try Int.fetchOne(db, sql: query) ?? 0
            guard owner == nil, identity == nil, objects == 0 else {
                throw Failure.malformedMetadata
            }
            try db.execute(sql: ownerSchema)
            try db.execute(sql: identitySchema)
            try db.execute(sql: "PRAGMA user_version = 2")
        case 1:
            guard sameSchema(owner, ownerSchema), identity == nil else {
                throw Failure.malformedMetadata
            }
            try db.execute(sql: identitySchema)
            try db.execute(sql: "PRAGMA user_version = 2")
        case 2:
            guard sameSchema(owner, ownerSchema), sameSchema(identity, identitySchema) else {
                throw Failure.malformedMetadata
            }
        default:
            throw Failure.malformedMetadata
        }
    }

    private static func tableSQL(_ name: String, in db: Database) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT sql FROM sqlite_master WHERE name = ? AND type = 'table'",
            arguments: [name])
    }

    private static func sameSchema(_ stored: String?, _ expected: String) -> Bool {
        guard let stored else { return false }
        return stored.split(whereSeparator: \.isWhitespace)
            == expected.split(whereSeparator: \.isWhitespace)
    }

    private static func readBootSession() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        guard let value = String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) else {
            return ""
        }
        return UUID(uuidString: value) == nil ? "" : value
    }

    /// `KERN_PROC_PID` start time. Nil when the process is gone or the sandbox
    /// withholds it, which callers treat as "unknown", never as "different".
    static func processStartTime(_ pid: Int32) -> Int64? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let status = name.withUnsafeMutableBufferPointer { mib in
            sysctl(mib.baseAddress, u_int(mib.count), &info, &size, nil, 0)
        }
        guard status == 0, size >= MemoryLayout<kinfo_proc>.size, info.kp_proc.p_pid == pid
        else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let micros = Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec)
        return micros > 0 ? micros : nil
    }
}

extension StoreProcessOwnership.Identity {
    /// A stamp is either unknown (empty / 0) or well formed.
    var hasValidStamp: Bool {
        startTime >= 0 && (bootSession.isEmpty || UUID(uuidString: bootSession) != nil)
    }
}
