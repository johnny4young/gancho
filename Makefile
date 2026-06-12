# Gancho developer entry points (pattern inherited from vitrine).
# `make help` lists targets.

XCODEGEN ?= xcodegen
SCHEME_MAC ?= Gancho
SCHEME_IOS ?= GanchoiOS
PACKAGE ?= Packages/GanchoKit

# When xcode-select points at CommandLineTools, `swift test` cannot find the
# Swift Testing module and `xcodebuild` is unavailable. Prefer the full Xcode
# toolchain whenever it is installed, without requiring `sudo xcode-select`.
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
ifneq ($(wildcard /Applications/Xcode.app),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

.PHONY: help project build build-ios test bench format lint hooks clean open

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-12s %s\n", $$1, $$2}'

project: ## Regenerate Gancho.xcodeproj from project.yml
	$(XCODEGEN) generate

build: project ## Build the macOS app (Debug, unsigned)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_MAC) -configuration Debug \
		CODE_SIGNING_ALLOWED=NO build

build-ios: project ## Build the iOS app (Debug, generic device, unsigned)
	xcodebuild -project Gancho.xcodeproj -scheme $(SCHEME_IOS) -configuration Debug \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

test: ## Run package unit tests (Swift Testing)
	swift test --package-path $(PACKAGE)

bench: ## Run the scale performance harness (seeds 100k rows; not for the PR loop)
	env GANCHO_PERF=1 swift test --package-path $(PACKAGE) --filter PerformanceHarnessTests

format: ## Format Swift sources in place
	swift format --in-place --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests

lint: ## Verify formatting without changing files
	swift format lint --strict --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests

hooks: ## Install the versioned git hooks (pre-commit lint)
	git config core.hooksPath scripts/githooks
	chmod +x scripts/githooks/*

clean: ## Remove generated project and build artifacts
	rm -rf Gancho.xcodeproj $(PACKAGE)/.build build DerivedData

open: project ## Open the generated project in Xcode
	open Gancho.xcodeproj
