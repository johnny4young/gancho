# Gancho developer entry points (pattern inherited from vitrine).
# `make help` lists targets.

XCODEGEN ?= xcodegen
SCHEME_MAC ?= Gancho
SCHEME_IOS ?= GanchoiOS
PACKAGE ?= Packages/GanchoKit

.PHONY: help project build build-ios test format lint clean open

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

format: ## Format Swift sources in place
	swift format --in-place --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests

lint: ## Verify formatting without changing files
	swift format lint --strict --recursive Apps $(PACKAGE)/Sources $(PACKAGE)/Tests

clean: ## Remove generated project and build artifacts
	rm -rf Gancho.xcodeproj $(PACKAGE)/.build build DerivedData

open: project ## Open the generated project in Xcode
	open Gancho.xcodeproj
