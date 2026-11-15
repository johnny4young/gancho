#if os(macOS)
    import Testing

    @testable import ClipboardCore

    @Suite("Running application names")
    @MainActor
    struct RunningApplicationNamesTests {
        private struct App: Equatable {
            let id: Int
        }

        private final class NameSource {
            var names: [Int: String] = [:]
            var reads: [Int] = []

            func name(_ app: App) -> String? {
                reads.append(app.id)
                return names[app.id]
            }
        }

        @Test("Each app's name is read once, when it arrives")
        func readsEachAppOnce() {
            let source = NameSource()
            source.names = [1: "Finder", 2: "zoom.us"]
            let index = RunningApplicationNames(seed: [App(id: 1), App(id: 2)], name: source.name)

            #expect(index.current().sorted() == ["Finder", "zoom.us"])
            source.names[3] = "CptHost"
            index.apply(inserted: [App(id: 3)], removed: [])
            #expect(index.current().sorted() == ["CptHost", "Finder", "zoom.us"])
            _ = index.current()

            #expect(source.reads == [1, 2, 3])
        }

        @Test("A removed app's name leaves the list")
        func removal() {
            let source = NameSource()
            source.names = [1: "Finder", 2: "CptHost"]
            let index = RunningApplicationNames(seed: [App(id: 1), App(id: 2)], name: source.name)

            index.apply(inserted: [], removed: [App(id: 2)])

            #expect(index.current() == ["Finder"])
        }

        @Test("A name not yet published is read again until it appears")
        func latePublishedName() {
            let source = NameSource()
            let index = RunningApplicationNames(seed: [], name: source.name)
            index.apply(inserted: [App(id: 7)], removed: [])
            #expect(index.current().isEmpty)

            source.names[7] = "ScreenSharingAgent"

            #expect(index.current() == ["ScreenSharingAgent"])
            _ = index.current()
            #expect(source.reads == [7, 7, 7])
        }

        @Test("A reset replaces the list")
        func reset() {
            let source = NameSource()
            source.names = [1: "Finder", 2: "CptHost"]
            let index = RunningApplicationNames(seed: [App(id: 2)], name: source.name)

            index.reset(to: [App(id: 1)])

            #expect(index.current() == ["Finder"])
        }
    }
#endif
