/// Exact top-K selection with O(K) retained values and O(log K) insertion.
/// `precedes` must be a strict total order, including tie-breaking; NaN keys
/// break the heap invariant, so callers filter them before inserting.
package struct BoundedTopK<Element: Sendable>: Sendable {
    private let limit: Int
    private let precedes: @Sendable (Element, Element) -> Bool
    private var heap: [Element] = []

    package init(limit: Int, by precedes: @escaping @Sendable (Element, Element) -> Bool) {
        self.limit = max(0, limit)
        self.precedes = precedes
    }

    package var count: Int { heap.count }
    package var sorted: [Element] { heap.sorted(by: precedes) }

    package mutating func insert(_ candidate: Element) {
        guard limit > 0 else { return }
        if heap.count < limit {
            heap.append(candidate)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard precedes(heap[parent], heap[child]) else { break }
                heap.swapAt(parent, child)
                child = parent
            }
            return
        }
        // The root is the worst retained candidate. An equal or worse value
        // cannot change the result and does not allocate or sort anything.
        guard precedes(candidate, heap[0]) else { return }
        heap[0] = candidate
        var parent = 0
        while parent < heap.count / 2 {
            let left = parent * 2 + 1
            let right = left + 1
            let child = right < heap.count && precedes(heap[left], heap[right]) ? right : left
            guard precedes(heap[parent], heap[child]) else { break }
            heap.swapAt(parent, child)
            parent = child
        }
    }
}
