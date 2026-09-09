# Verifying entitlement-dependent behavior without a device

Some questions look like they need a physical iPhone and do not. Signing
identity, team prefix, App Group and keychain access group are all decided at
**code-signing time**, on the Mac, from files that are already on disk — so
they can be read directly instead of inferred from an app's behavior on a
device.

This matters because the alternative is expensive and often unfalsifiable: a
"device day" that observes nothing tells you nothing, and it is easy to gate a
change on one without noticing that success and silent failure would look
identical.

Work down this ladder and stop at the first rung that answers the question.

## Rung 1 — the provisioning profiles (no build)

Profiles live in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.
They are CMS-signed plists; `security cms -D` decodes them.

```bash
cd ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/
for f in *.mobileprovision *.provisionprofile; do
  plist=$(security cms -D -i "$f" 2>/dev/null) || continue
  name=$(printf '%s' "$plist" | plutil -extract Name raw - 2>/dev/null)
  case "$name" in *[Gg]ancho*) ;; *) continue ;; esac
  echo "### $name"
  printf '%s' "$plist" | plutil -extract ApplicationIdentifierPrefix.0 raw - | sed 's/^/  prefix: /'
  printf '%s' "$plist" | plutil -extract TeamIdentifier.0 raw - | sed 's/^/  team:   /'
  printf '%s' "$plist" | plutil -extract 'Entitlements.keychain-access-groups' xml1 -o - - 2>/dev/null \
    | grep -o '<string>[^<]*</string>' | sed 's/<[^>]*>//g;s/^/  permits: /'
done
```

Answers: **is the App Identifier Prefix the same as the Team ID?** They differ
only for legacy or transferred App IDs, and that difference is the entire
reason `$(AppIdentifierPrefix)` exists as a separate variable from
`DEVELOPMENT_TEAM`.

Note that a Team Provisioning Profile permits a wildcard
(`TEAMID.*`). The profile says what is *allowed*, not what the binary *asks
for* — that is rung 2.

## Rung 2 — the signed binary (build, no device)

`make build-ios` builds with `CODE_SIGNING_ALLOWED=NO`, so it produces
nothing to inspect. Ask for a signed device build explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -disableAutomaticPackageResolution -project Gancho.xcodeproj -scheme GanchoiOS \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=JGWX5ZT2N2 build
```

Then read what was actually baked in, for the app **and every extension** —
they are separate targets with separate entitlements, and a mismatch between
them is the failure mode worth catching:

`/bin/ls` on purpose: the maintainer's shell aliases `ls` to `eza`, which
rejects `-t` as written. `-t | head -1` takes the NEWEST — there is usually
more than one `Gancho-*` DerivedData directory, and reading a stale one is the
easiest way to get a confidently wrong answer here.

```bash
APP=$(/bin/ls -dt ~/Library/Developer/Xcode/DerivedData/Gancho-*/Build/Products/Debug-iphoneos/GanchoiOS.app | head -1)
for t in "$APP" "$APP"/PlugIns/*.appex; do
  echo "### ${t##*/}"
  codesign -d --entitlements :- "$t" 2>/dev/null | plutil -convert xml1 -o - - \
    | awk '/keychain-access-groups/,/<\/array>/' \
    | grep -o '<string>[^<]*</string>' | sed 's/<[^>]*>//g;s/^/  group: /'
done
```

Answers: **what group does each target actually hold, fully expanded**, and
**how many** — which matters wherever code assumes "the first entitled group".

## Rung 3 — runtime, which needs a real device

The Simulator cannot answer entitlement questions for this project. A
simulator build is **ad-hoc signed with an empty entitlements dictionary**:

```
$ codesign -dv …/Debug-iphonesimulator/GanchoiOS.app
Signature=adhoc
TeamIdentifier=not set
$ codesign -d --entitlements - …/Debug-iphonesimulator/GanchoiOS.app
[Dict]          # empty
```

The `keychain-access-groups` string is present in the binary as data, but
nothing applies it. Anything that reads back an access group at runtime will
report a simulator default, not the group the OS would grant a signed build.

So rung 3 is genuinely device-only — and before spending a device day on it,
make sure the thing you want to observe is **observable**. If the only
user-visible signal is an error path, then a healthy device produces no output
and the day proves nothing. Add the positive signal first, or accept that
silence is the result and say so.

## Recorded answer for this account

Measured 2026-09-09 against the four iOS Team Provisioning Profiles and a
signed `Debug-iphoneos` build:

| Target | App ID prefix | Team ID | Signed keychain group |
| --- | --- | --- | --- |
| `com.johnny4young.gancho` | `JGWX5ZT2N2` | `JGWX5ZT2N2` | `JGWX5ZT2N2.com.johnny4young.gancho.keys` |
| `…gancho.share` | `JGWX5ZT2N2` | `JGWX5ZT2N2` | same |
| `…gancho.keyboard` | `JGWX5ZT2N2` | `JGWX5ZT2N2` | same |
| `…gancho.widgets` | `JGWX5ZT2N2` | `JGWX5ZT2N2` | same |

Exactly one group per target, and the prefix equals the team ID. The build-time
value `KeychainPassphraseStore.iosSharedAccessGroup` computes the identical
string, so on this account the app and all three extensions already resolve the
same, correct group.

Re-run rungs 1 and 2 if the app is ever transferred to another team or account,
which is the case that makes the prefix and the team ID diverge.
