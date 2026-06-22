# Gancho developer entry points (pattern inherited from vitrine).
# `make help` lists targets.

XCODEGEN ?= xcodegen
SCHEME_MAC ?= Gancho
SCHEME_IOS ?= GanchoiOS
PACKAGE ?= Packages/GanchoKit
# macOS 26+ requires the XCUITest runner to be signed. Keep automatic signing
# explicit by default, and let CI override this when it provides custom signing
# settings (for example: make test-ui TEST_UI_SIGNING_FLAGS="DEVELOPMENT_TEAM=...").
TEST_UI_SIGNING_FLAGS ?= CODE_SIGNING_ALLOWED=YES

# When xcode-select points at CommandLineTools, `swift test` cannot find the
# Swift Testing module and `xcodebuild` is unavailable. Prefer the full Xcode
# toolchain whenever it is installed, without requiring `sudo xcode-select`.
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
ifneq ($(wildcard /Applications/Xcode.app),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

.PHONY: help project build build-ios test test-ui bench format lint hooks clean open

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-12s %s\n", $$1, $$2}'

project: ## Regenerate Gancho.xcodeproj from project.yml
	$(XCODEGEN) generate

build: project ## Build the macOS app (Debug, unsigned)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_MAC) -configuration Debug \
		CODE_SIGNING_ALLOWED=NO build

build-signed: project ## Build the macOS app (Debug, team-signed) — stable identity so the Accessibility grant persists across rebuilds (paste-back testing)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_MAC) -configuration Debug \
		CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=JGWX5ZT2N2 build

build-ios: project ## Build the iOS app (Debug, generic device, unsigned)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_IOS) -configuration Debug \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

test: ## Run package unit tests (Swift Testing)
	swift test --package-path $(PACKAGE)

bench: ## Run the scale performance harness (seeds 100k rows; not for the PR loop)
	env GANCHO_PERF=1 swift test --package-path $(PACKAGE) --filter PerformanceHarnessTests

test-ui: project ## Run the XCUITest smoke suite (drives the real app; signed runner)
	xcodebuild test -project Gancho.xcodeproj -scheme $(SCHEME_MAC) \
		-only-testing:GanchoUITests $(TEST_UI_SIGNING_FLAGS)

format: ## Format Swift sources in place
	swift format --in-place --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests Tests

lint: ## Verify formatting without changing files
	swift format lint --strict --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests Tests

hooks: ## Install the versioned git hooks (pre-commit lint)
	git config core.hooksPath scripts/githooks
	chmod +x scripts/githooks/*

clean: ## Remove generated project and build artifacts
	rm -rf Gancho.xcodeproj $(PACKAGE)/.build build DerivedData

open: project ## Open the generated project in Xcode
	open Gancho.xcodeproj
