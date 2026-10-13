# Native KeyboardShortcuts acceptance

These optional macOS XCUITests build disposable, signed dependency hosts from
the **actual revision in `Dependencies/Package.resolved`**. Its version must
also match the exact requirement in `project.yml` and the upstream canary pin.
The script archives that revision from an existing local Git repository, so
the test neither fetches packages nor uses an edited dependency checkout.

Run on an unlocked Mac with Xcode, XcodeGen, Python 3, and an existing trusted
signing identity:

```bash
KEYBOARDSHORTCUTS_CHECKOUT=/path/to/KeyboardShortcuts \
SHORTCUT_MENU_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
./scripts/test-keyboard-shortcuts-menu.sh
```

The equivalent menu target is `make test-shortcuts-menu`. Run the recorder
gate separately with the same environment:

```bash
KEYBOARDSHORTCUTS_CHECKOUT=/path/to/KeyboardShortcuts \
SHORTCUT_MENU_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
make test-shortcuts-recorder
```

`SHORTCUT_ACCEPTANCE_SCOPE=recorder ./scripts/test-keyboard-shortcuts-menu.sh`
selects that same recorder gate. Neither target launches Gancho or runs its
complete UI suite. Run only one native gate at a time on an unlocked desktop.

## Menu event consumption

The test opens a real `NSMenu` and sends one native
Command-Control-Option-Shift-V key pair. It requires exactly one down callback
and one up callback while the menu is open, both non-repeat. Transparent
`NSApplication` forwarding records only that chord's event metadata; each
callback must match one event dequeued in the tracking run-loop mode. The
consumed chord must never be reposted or forwarded to ordinary `sendEvent`,
including after the menu closes. This detects the consumed-event return-value
regression without requiring a particular passing dependency version.
Input is synthesized by XCUITest. The chord uses ANSI virtual key code 9;
the test validates matching metadata and proves behavior on the keyboard
layout actually exercised, without claiming other layouts were tested.

The menu fixture compiles Gancho's stable shortcut-name catalog, but has no
Gancho composition root, clipboard, database, cloud, telemetry, paste writer, or
installed-app identity. It registers only its synthetic four-modifier chord
and resets only its fresh UUID preferences domain. XCUITest input is globally
synthesized: naming a target application does not guarantee delivery. Before
each click or key, the tests require the fixture to be foreground in both
XCTest and AppKit, and abort on missing windows or controls. The menu gate also
requires its synthetic chord to have an active registration before input; an
unavailable binding must fail before sending a potentially conflicting chord.
There is still a
focus race between the check and the event; keep the desktop reserved during
execution. The fixture uses no global event tap or fixture-side event posting.
Neither gate changes automation, Accessibility, or notification permissions;
report an authorization or focus failure as a blocked gate.

## Recorder and persisted binding restoration

The separate recorder host compiles Gancho's shortcut catalog and the
Foundation-only `ShortcutConflicts` checker unchanged, then hosts the actual SwiftUI
`KeyboardShortcuts.Recorder` in an `NSHostingView`. Inert down/up counters use the
registration APIs used by Gancho's panel and optional actions. Synthetic raw
Carbon JSON is seeded into its UUID standard-defaults domain before the first
shortcut name is accessed, preventing initial defaults from hiding a failed
restoration. All seeded chords use four modifiers and ordinary letter keys.

Five focused tests cover:

1. Preserved raw preferences, displayed bindings, enabled registration, and one
   native down/up pair for each synthetic binding.
2. Escape cancellation, recorder switching, and a neutral outside click, with
   unchanged values and resumed dispatch.
3. Re-recording the existing menu-bound binding without a self-conflict alert,
   including no action dispatch from the recording gesture's final key-up.
4. Replacement, inactive old binding, single delivery of the new binding, and
   a true relaunch using the same UUID domain without reset or reseeding.
5. Real fixture-menu conflict rejection, native optional-binding clearing, and
   an absent stored binding with inactive registration across relaunch.

The runner waits for both native recorders, guards each gesture, requires
actual recorder focus before recording keys, and removes only its validated
UUID domain after each complete case, including failure cleanup. The host
preserves that domain at termination so
relaunch tests exercise storage. The wrapper enforces all five tests passed,
zero failures, zero skips, zero expected failures, and a Passed result;
lack of focus must fail before input is sent.

This gate exercises the native dependency recorder and Gancho's unchanged
shortcut-name contract on the tested runtime/layout. Menu-conflict rejection
uses the dependency's native conflict handling. The compiled Gancho conflict
checker is called for successful synthetic chords; its full reserved-system
shortcut table is not exercised by this fixture. The gate does not host the actual
Settings or onboarding views, execute Gancho's paste/capture actions, start its
composition root, or prove helper/APNs/StoreKit/Sparkle startup. Minimum macOS
15.4 and physical/function-key routes need their own runtime evidence.

The signed macOS 26.6.2 run on exact 3.0.1 passed four recorder cases. The
unchanged-binding case remained in recording mode with zero changes/actions
and preserved preferences. The same fixture case passed on unmodified 3.1.0;
the locked 3.0.1 version also matches the base branch. Keep this case failing
until the dependency satisfies it. A passing menu gate does not imply a
passing recorder gate, and neither implies complete Gancho or release acceptance.

The script prints a fresh `gancho-shortcut-menu.*` evidence directory and
retains its manifest, JSON trace or recorder snapshot, log, and `.xcresult`.
The manifest records production-source hashes, separate UUID identities, and
the exact locked dependency revision. These gates do not prove full Gancho
startup, Settings/onboarding recorder integration, the installed app, or
runtime behavior on macOS versions not actually tested.
