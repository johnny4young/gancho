import Foundation
import Testing

@testable import GanchoKit

@Suite("Byte sizes — human readable")
struct ByteSizeTests {
    @Test("kilobyte- and megabyte-scale values use KB / MB, not raw bytes")
    func scalesUnits() {
        let kb = ByteSize.formatted(734_053)
        #expect(kb.contains("KB"))
        #expect(!kb.contains("734053"))

        #expect(ByteSize.formatted(12_957_256).contains("MB"))
    }
}
