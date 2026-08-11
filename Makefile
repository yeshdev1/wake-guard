# WakeGuard developer tasks (WG-003, WG-004).
# Bootstrap on a clean machine: `brew install xcodegen swiftlint` then `make test`.
# (swift-format ships with the Swift 6 toolchain.)

PROJECT     := WakeGuard.xcodeproj
SCHEME      := WakeGuard
SOURCES     := Sources Tests UITests
# Override on the CLI, e.g. make test DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=26.5'
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=26.5

.PHONY: generate build test test-fast test-ui lint format format-check check-tracking ci ci-fast clean archive export release-notes

# WG-260: TestFlight / App Store pipeline paths + build number.
ARCHIVE_PATH ?= build/WakeGuard.xcarchive
EXPORT_PATH  ?= build/export
# Reproducible build number (commit count); override per upload with BUILD=<n>.
BUILD        ?= $(shell scripts/release_metadata.sh build-number)

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)'

# Set RESULT_BUNDLE=path.xcresult to emit a result bundle (used by CI artifacts).
# xcodebuild refuses to overwrite an existing bundle, so remove a stale one first.
test: generate
	$(if $(RESULT_BUNDLE),rm -rf '$(RESULT_BUNDLE)',)
	xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		$(if $(RESULT_BUNDLE),-resultBundlePath '$(RESULT_BUNDLE)',)

# Fast dev-loop test: incremental build, NO xcodegen regen, reuses DerivedData.
# Narrow with ONLY=, e.g. make test-fast ONLY=WakeGuardTests/DefaultAlarmPolicyEngineTests
# Run `make generate` yourself after ADDING or REMOVING source files (XcodeGen globs).
test-fast:
	xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		$(if $(ONLY),-only-testing:$(ONLY),)

# WG-050: XCUITest flows (create/edit/delete/critical/travel) via the WakeGuardUITests scheme.
# Slower than the unit suite (launches the app), so it is NOT part of ci-fast; run on demand.
test-ui: generate
	xcodebuild test \
		-project $(PROJECT) -scheme WakeGuardUITests \
		-destination '$(DESTINATION)' \
		$(if $(RESULT_BUNDLE),-resultBundlePath '$(RESULT_BUNDLE)',)

# WG-260: internal TestFlight pipeline. `release-notes` prints build metadata + notes from git;
# `archive` builds a device archive stamped with the reproducible build number; `export` produces an
# .ipa via ExportOptions.plist. Signing + the App Store Connect upload need real Apple credentials on a
# provisioned machine (not this sandbox) — see docs/RELEASE_PIPELINE.md for the manual upload step.
release-notes:
	@scripts/release_metadata.sh

# Remove any prior archive first so `export` can never repackage a stale build from an earlier commit.
archive: generate
	rm -rf '$(ARCHIVE_PATH)'
	xcodebuild archive \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-archivePath '$(ARCHIVE_PATH)' \
		CURRENT_PROJECT_VERSION=$(BUILD)

# Export the .ipa from the archive just built. Run `make archive` immediately before this (a fresh
# archive per upload) — export intentionally does not re-archive so an externally-built archive can be
# exported, but it must be the current one; the archive step clears stale output to keep that safe.
export:
	rm -rf '$(EXPORT_PATH)'
	xcodebuild -exportArchive \
		-archivePath '$(ARCHIVE_PATH)' \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath '$(EXPORT_PATH)'

lint:
	swiftlint lint --strict --config .swiftlint.yml

format:
	swift format --in-place --recursive $(SOURCES)

format-check:
	swift format lint --strict --recursive $(SOURCES)

# WG-006: verify every backlog task is tracked, with evidence for active tasks.
check-tracking:
	python3 scripts/task_tracking.py --check

# CI quality gate: tracking + formatting + lint, then build + test (warnings-as-errors).
# This is the canonical pipeline gate (regenerates the project); keep it for CI.
ci: check-tracking format-check lint test

# Fast local dev-loop gate: identical checks to `ci` but NO xcodegen regen and a single
# incremental build (run `make generate` first if files were added/removed). Use this
# between tasks instead of a separate narrow run followed by a full `ci` — one green
# `ci-fast` is the local gate, and it matches remote CI's checks.
ci-fast: check-tracking format-check lint test-fast

# clean also removes .build (SwiftPM output), for when ADR-003 package
# extraction lands; harmless while the build is XcodeGen-only.
clean:
	rm -rf $(PROJECT) DerivedData .build
