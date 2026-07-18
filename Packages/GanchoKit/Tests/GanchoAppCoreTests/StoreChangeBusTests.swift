import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Store change bus — content-free mutation fan-out")
struct StoreChangeBusTests {
    @Test("One subscriber receives every posted change in order")
    func singleSubscriberInOrder() async {
        let bus = StoreChangeBus()
        let stream = bus.subscribe()
        // Give subscribe() time to register before posting.
        while bus.subscriberCount == 0 { await Task.yield() }

        bus.post(.clips)
        bus.post(.boards)
        bus.post(.curation)

        var received: [StoreChange] = []
        for await change in stream {
            received.append(change)
            if received.count == 3 { break }
        }
        #expect(received == [.clips, .boards, .curation])
    }

    @Test("Every subscriber receives a broadcast; a batch posts its whole set")
    func fanOutAndBatch() async {
        let bus = StoreChangeBus()
        let a = bus.subscribe()
        let b = bus.subscribe()
        while bus.subscriberCount < 2 { await Task.yield() }

        bus.post([.clips, .curation])

        func collect(_ stream: AsyncStream<StoreChange>) async -> Set<StoreChange> {
            var seen: Set<StoreChange> = []
            for await change in stream {
                seen.insert(change)
                if seen == [.clips, .curation] { break }
            }
            return seen
        }
        async let seenA = collect(a)
        async let seenB = collect(b)
        #expect(await seenA == [.clips, .curation])
        #expect(await seenB == [.clips, .curation])
    }

    @Test("A terminated subscription drops off the bus")
    func terminationDropsSubscriber() async {
        let bus = StoreChangeBus()
        do {
            let stream = bus.subscribe()
            while bus.subscriberCount == 0 { await Task.yield() }
            _ = stream  // used within scope
            #expect(bus.subscriberCount == 1)
        }
        // The stream's continuation terminates when the AsyncStream is dropped;
        // poll until the bus observes it (termination is asynchronous).
        var deadline = 200
        while bus.subscriberCount != 0, deadline > 0 {
            await Task.yield()
            deadline -= 1
        }
        #expect(bus.subscriberCount == 0)
    }

    // MARK: - Coalescing (deterministic, no timing)

    @Test("Accumulator unions a burst and only the latest ticket flushes")
    func accumulatorUnionsAndGuardsStaleFlush() async {
        let accumulator = StoreChangeAccumulator()
        let t1 = await accumulator.add(.clips)
        _ = await accumulator.add(.boards)
        let t3 = await accumulator.add(.clips)  // duplicate collapses in the union

        // A stale flush (an earlier ticket) never fires.
        #expect(await accumulator.flush(ticket: t1) == nil)
        // The latest ticket flushes the whole union once.
        #expect(await accumulator.flush(ticket: t3) == [.clips, .boards])
        // Drained: a repeat flush is empty.
        #expect(await accumulator.flush(ticket: t3) == nil)
    }

    @Test("A quiet-separated burst emits exactly one coalesced batch")
    func coalescerEmitsOneBatchPerBurst() async {
        // The source is fully buffered before consumption. The injected yield
        // lets each replaced debounce task observe cancellation without using
        // wall-clock timing.
        let coalescer = StoreChangeCoalescer(
            window: .zero, sleep: { _ in await Task.yield() })
        let (source, continuation) = AsyncStream.makeStream(of: StoreChange.self)

        continuation.yield(.clips)
        continuation.yield(.boards)
        continuation.yield(.clips)
        continuation.finish()

        var batches: [StoreChangeBatch] = []
        for await batch in coalescer.batches(of: source) {
            batches.append(batch)
        }
        #expect(batches == [[.clips, .boards]])
    }
}
