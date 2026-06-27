# Homebrew cask for Gancho.
#
# This file is the source template that lives in the app repo; the released cask
# lives in the tap (johnny4young/homebrew-tap, `Casks/gancho.rb`). On each
# release, .github/workflows/update-cask.yml regenerates the tap cask from this
# template (everything from the `cask` line down) with the published version and
# the DMG's SHA-256. See docs/RELEASING.md.
#
cask "gancho" do
  version "0.1.0"
  sha256 "6b4af3b643505d96b463bb3e97668571281c47c231c925af62ec94a2fd92cc7e"

  url "https://github.com/johnny4young/gancho/releases/download/v#{version}/Gancho-#{version}.dmg"
  name "Gancho"
  desc "Privacy-first smart clipboard manager"
  homepage "https://github.com/johnny4young/gancho"

  # Stable GitHub release-tag URLs, so livecheck tracks new versions from the
  # releases page.
  livecheck do
    url :url
    strategy :github_latest
  end

  # Gancho keeps itself current in place via Sparkle (direct-download channel),
  # so Homebrew should not flag user-updated copies as outdated.
  auto_updates true
  depends_on macos: :tahoe

  app "Gancho.app"
  # The `gancho` CLI + local MCP server ships inside the bundle. It is named
  # gancho-cli there so it does not collide with the `Gancho` app executable on
  # case-insensitive APFS; surface it on PATH under its real name.
  binary "#{appdir}/Gancho.app/Contents/MacOS/gancho-cli", target: "gancho"

  zap trash: [
    "~/Library/Application Support/Gancho",
    "~/Library/Caches/com.johnny4young.gancho",
    "~/Library/HTTPStorages/com.johnny4young.gancho",
    "~/Library/Preferences/com.johnny4young.gancho.menubar-helper.plist",
    "~/Library/Preferences/com.johnny4young.gancho.plist",
  ]
end
