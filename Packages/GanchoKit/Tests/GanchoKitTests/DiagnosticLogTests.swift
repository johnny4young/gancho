import Foundation
import Testing

@testable import GanchoKit

@Suite("Diagnostic log — capped, ordered, content-free")
struct DiagnosticLogTests {
    @Test("Keeps only the most recent entries up to the cap, in order")
    func capped() {
        let log = DiagnosticLog(cap: 3)
        for i in 1...5 {
            log.record("store", "msg \(i)", at: Date(timeIntervalSince1970: Double(i)))
        }
        let entries = log.entries
        #expect(entries.count == 3)
        #expect(entries.map(\.message) == ["msg 3", "msg 4", "msg 5"])
        #expect(entries.map(\.category) == ["store", "store", "store"])
    }

    @Test("Empty by default; record appends; clear() empties it")
    func emptyRecordClear() {
        let log = DiagnosticLog()
        #expect(log.entries.isEmpty)
        log.record("sync", "iCloud paused")
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.message == "iCloud paused")
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("Concurrent writers preserve the cap and complete entries")
    func concurrentWriters() async {
        let cap = 64
        let log = DiagnosticLog(cap: cap)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<1_000 {
                group.addTask {
                    log.record(
                        "stress", "message-\(index)",
                        at: Date(timeIntervalSince1970: Double(index)))
                }
            }
        }

        let entries = log.entries
        #expect(entries.count == cap)
        #expect(Set(entries.map(\.id)).count == cap)
        #expect(entries.allSatisfy { $0.category == "stress" })
        #expect(entries.allSatisfy { $0.message.hasPrefix("message-") })
    }
}
