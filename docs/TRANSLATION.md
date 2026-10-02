# On-device translation

Smart Paste translation has two independent capabilities:

- An installed source/target pair uses Apple's Translation framework on macOS 26 or iOS 26. It does not require Apple Intelligence.
- The existing generative fallback is available only when Apple Intelligence is usable. Downloadable, unsupported or unidentified pairs cannot start this fallback without that capability.

The native session's minimum version has not changed. Gancho still runs on macOS 15.4; this implementation does not promise native translation on that version. No language downloads are initiated automatically.

With Smart Paste enabled, the menu checks each destination for the current text. Unavailable destinations are disabled. Returning to the app or changing the text refreshes availability; execution checks again, since language assets can change after the menu opens.

Translation is local. Both engines receive the same existing sanitized input. The result is temporary for review; cancellation and empty answers are not delivered as copyable content. If neither engine can answer, Gancho explains how to install the pair or enable Apple Intelligence without changing system settings itself.

This describes the source implementation after v0.9.1, not a feature already published in that release.

Smart Paste appears only after the full, unmasked text payload has loaded. A metadata preview must not be translated as though it were the complete clip. Compact translated/large-text menus wrap instead of overflowing the peek.
