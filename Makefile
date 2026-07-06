# Gancho developer entry points.
# `make help` lists targets.

XCODEGEN ?= xcodegen
SCHEME_MAC ?= Gancho
SCHEME_IOS ?= GanchoiOS
PACKAGE ?= Packages/GanchoKit
# Default signing team for local signed builds. Override for forks/CI with
# `make install-ios DEVELOPMENT_TEAM=<team-id>`.
DEVELOPMENT_TEAM ?= JGWX5ZT2N2
# Target a specific device for `install-ios` with `make install-ios IOS_DEVICE=<uuid>`.
# Left empty, install-ios auto-detects the connected iPhone/iPad (in the recipe,
# where DEVELOPER_DIR is exported — macOS's make 3.81 doesn't pass it to $(shell)).
IOS_DEVICE ?=
# macOS 26+ requires the XCUITest runner to be signed. Keep automatic signing
# explicit by default, and let CI override this when it provides custom signing
# settings (for example: make test-ui TEST_UI_SIGNING_FLAGS="DEVELOPMENT_TEAM=...").
TEST_UI_SIGNING_FLAGS ?= CODE_SIGNING_ALLOWED=YES
# Direct-download license signing (honor model). Empty by default — a
# from-source or App Store build cannot mint license tokens. The release DMG
# build exports the real values. Exported so xcodegen picks them up.
export GANCHO_LICENSE_SIGNING_KEY ?=
export GANCHO_COMPILATION_CONDITIONS ?=

# When xcode-select points at CommandLineTools, `swift test` cannot find the
# Swift Testing module and `xcodebuild` is unavailable. Prefer the full Xcode
# toolchain whenever it is installed, without requiring `sudo xcode-select`.
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
ifneq ($(wildcard /Applications/Xcode.app),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

.PHONY: help project fetch-sparkle build build-signed build-ios install-ios test test-ui bench format lint release-check package-macos package-dmg appcast qa-release site-check hooks clean open

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-12s %s\n", $$1, $$2}'

fetch-sparkle: ## Fetch the pinned Sparkle.framework into Vendor/ (auto-updater)
	./scripts/fetch-sparkle.sh

project: fetch-sparkle ## Regenerate Gancho.xcodeproj from project.yml
	$(XCODEGEN) generate

build: project ## Build the macOS app (Debug, unsigned)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_MAC) -configuration Debug \
		CODE_SIGNING_ALLOWED=NO build

build-signed: project ## Build the macOS app (Debug, team-signed) — stable identity so the Accessibility grant persists across rebuilds (paste-back testing)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_MAC) -configuration Debug \
		CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) build

build-ios: project ## Build the iOS app (Debug, generic device, unsigned)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_IOS) -configuration Debug \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

install-ios: project ## Build the iOS app (Debug, team-signed) and install it on the connected iPhone/iPad
	@dev="$(IOS_DEVICE)"; \
	if [ -z "$$dev" ]; then \
		dev="$$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' | grep -i connected | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' | head -1)"; \
	fi; \
	if [ -z "$$dev" ]; then \
		echo "No connected iPhone/iPad found — plug one in and trust this Mac (see: xcrun devicectl list devices)"; exit 1; \
	fi; \
	echo "Installing on device $$dev…"; \
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_IOS) -configuration Debug \
		-destination 'generic/platform=iOS' -derivedDataPath build/ios \
		CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) -allowProvisioningUpdates build && \
	xcrun devicectl device install app --device "$$dev" \
		build/ios/Build/Products/Debug-iphoneos/GanchoiOS.app

test: ## Run package unit tests (Swift Testing)
	swift test --package-path $(PACKAGE)

bench: ## Run the scale performance harness (seeds 100k rows; not for the PR loop)
	env GANCHO_PERF=1 swift test --package-path $(PACKAGE) --filter PerformanceHarnessTests

test-ui: project ## Run the XCUITest smoke suite (drives the real app; signed runner)
	xcodebuild test -project Gancho.xcodeproj -scheme $(SCHEME_MAC) \
		-only-testing:GanchoUITests $(TEST_UI_SIGNING_FLAGS)

test-sync-e2e: project ## Live two-engine sync harness vs the REAL dev container (owner-gated; signed host + iCloud)
	TEST_RUNNER_GANCHO_SYNC_E2E=1 xcodebuild test -project Gancho.xcodeproj -scheme $(SCHEME_MAC) \
		-only-testing:GanchoSyncE2ETests \
		CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)

# Override the simulator with: make test-ui-ios IOS_SIM_DEST='platform=iOS Simulator,name=iPhone 17'
IOS_SIM_DEST ?= platform=iOS Simulator,name=iPhone 17
test-ui-ios: project ## Run the iOS XCUITest smoke suite on a simulator
	xcodebuild test -project Gancho.xcodeproj -scheme $(SCHEME_IOS) \
		-only-testing:GanchoiOSUITests \
		-destination '$(IOS_SIM_DEST)' CODE_SIGNING_ALLOWED=NO

format: ## Format Swift sources in place
	swift format --in-place --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests Tests

lint: ## Verify formatting without changing files
	swift format lint --strict --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests Tests

release-check: ## Verify release metadata/version sync before tagging
	./scripts/check-version-sync.sh

package-macos: release-check project ## Build and package the macOS Release app as dist/Gancho-<version>.zip
	./scripts/package-macos-zip.sh

package-dmg: release-check ## Build the direct-download (license) flavor and package it as a signed DMG
	./scripts/package-macos-dmg.sh

appcast: ## Sign the dist/*.dmg and refresh site/appcast.xml (maintainer Keychain EdDSA key)
	./scripts/generate-appcast.sh

qa-release: ## QA the newest dist/Gancho-*.zip or a provided ARTIFACT=/path/to/Gancho.app
	./scripts/qa-release.sh $${ARTIFACT:-}

site-check: ## Verify the static GitHub Pages site structure
	./scripts/check-site.sh

hooks: ## Install the versioned git hooks (pre-commit lint; pre-push lint+tests, skipped without a Swift toolchain)
	git config core.hooksPath scripts/githooks
	chmod +x scripts/githooks/*

clean: ## Remove generated project and build artifacts
	rm -rf Gancho.xcodeproj $(PACKAGE)/.build build DerivedData

open: project ## Open the generated project in Xcode
	open Gancho.xcodeproj
