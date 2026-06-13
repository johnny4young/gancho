#if os(macOS)
    import Testing

    @testable import ClipboardCore

    @Suite("Shortcut conflict warnings")
    struct ShortcutConflictsTests {
        @Test("System staples are flagged with their owner")
        func systemStaples() {
            #expect(ShortcutConflicts.conflict(with: "⌘V") == "Paste")
            #expect(ShortcutConflicts.conflict(with: "⇧⌘4") == "Screenshot Selection")
            #expect(ShortcutConflicts.conflict(with: "⌘Space") == "Spotlight")
        }

        @Test("Normalization tolerates case and whitespace")
        func normalization() {
            #expect(ShortcutConflicts.conflict(with: "⌘v") == "Paste")
            #expect(ShortcutConflicts.conflict(with: "⇧ ⌘ 4") == "Screenshot Selection")
        }

        @Test("Free combos return nil")
        func freeCombos() {
            #expect(ShortcutConflicts.conflict(with: "⇧⌘V") == nil)
            #expect(ShortcutConflicts.conflict(with: "⌃⌥G") == nil)
        }
    }
#endif
