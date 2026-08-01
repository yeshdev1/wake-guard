# WakeGuard developer tasks (WG-003, WG-004).
# Bootstrap on a clean machine: `brew install xcodegen swiftlint` then `make test`.
# (swift-format ships with the Swift 6 toolchain.)

PROJECT     := WakeGuard.xcodeproj
SCHEME      := WakeGuard
SOURCES     := Sources Tests
# Override on the CLI, e.g. make test DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=26.5'
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=26.5

.PHONY: generate build test lint format format-check ci clean

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

lint:
	swiftlint lint --strict --config .swiftlint.yml

format:
	swift format --in-place --recursive $(SOURCES)

format-check:
	swift format lint --strict --recursive $(SOURCES)

# CI quality gate: formatting check, lint, then build + test (warnings-as-errors).
ci: format-check lint test

# clean also removes .build (SwiftPM output), for when ADR-003 package
# extraction lands; harmless while the build is XcodeGen-only.
clean:
	rm -rf $(PROJECT) DerivedData .build
