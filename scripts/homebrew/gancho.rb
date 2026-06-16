# Homebrew formula for the `gancho` CLI + local MCP server.
#
# This is the distribution TEMPLATE. Publishing is owner-gated: at release,
# fill `url`/`sha256` from the tagged source tarball and push this file to a
# tap (e.g. `johnny4young/homebrew-tap`). Until then it documents exactly how
# `brew install gancho` builds the tool from source.
#
#   brew tap johnny4young/tap
#   brew install gancho
class Gancho < Formula
  desc "Privacy-first clipboard CLI and local MCP server for Gancho"
  homepage "https://gancho.app"
  # TODO(release): point at the tagged source tarball and fill the checksum.
  url "https://github.com/johnny4young/gancho/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT" # TODO(owner): confirm the license before publishing.

  # Builds from source with the Swift toolchain that ships in Xcode 26.
  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe

  def install
    system "swift", "build", "--disable-sandbox", "--configuration", "release",
           "--package-path", "Packages/GanchoKit", "--product", "gancho"
    bin.install ".build/release/gancho"
  end

  test do
    # `help` prints usage without touching the user's store.
    assert_match "gancho", shell_output("#{bin}/gancho help")
  end
end
