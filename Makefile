# WakeGuard developer tasks (WG-003).
# Bootstrap on a clean machine: `brew install xcodegen` then `make test`.

PROJECT     := WakeGuard.xcodeproj
SCHEME      := WakeGuard
# Override on the CLI, e.g. make test DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=26.5'
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=26.5

.PHONY: generate build test clean

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)'

test: generate
	xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)'

# clean also removes .build (SwiftPM output), for when ADR-003 package
# extraction lands; harmless while the build is XcodeGen-only.
clean:
	rm -rf $(PROJECT) DerivedData .build
