import Darwin
import Foundation
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

/// Archive files are read in 64 KB chunks. A chunk the loop leaks to an outer
/// autorelease pool stays alive until that pool drains, so this measures inside
/// one: whatever a read leaks is still counted.
@Suite("Portable archive — bounded memory while reading files")
struct GanchoArchiveMemoryTests {
    private static func sparseFile(bytes: UInt64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-memory-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: bytes)
        try handle.close()
        return url
    }

    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    @Test("Verifying an exported file's checksum keeps the footprint small")
    func digestKeepsTheFootprintSmall() throws {
        let size: UInt64 = 256 << 20
        let url = try Self.sparseFile(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }

        let growth = try autoreleasepool { () throws -> Int64 in
            let before = Self.footprint()
            _ = try GanchoArchive.fileDigest(url)
            return Self.footprint() - before
        }
        #expect(growth < Int64(size / 4), "hashing \(size) bytes grew the footprint by \(growth)")
    }
}
