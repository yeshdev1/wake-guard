#!/usr/bin/env bash
# WG-260: generate build metadata + release notes for a TestFlight build.
#
# Usage:
#   scripts/release_metadata.sh                # full metadata block + release notes (stdout)
#   scripts/release_metadata.sh build-number   # just the build number (for `make archive`)
#
# The build number is the commit count on HEAD (monotonic, reproducible from the repo), so two
# archives of the same commit carry the same build metadata. Release notes are the commit subjects
# since the last git tag (or the last 20 commits if there is no tag). Pure git — no network, no
# credentials; the signed archive/upload that consumes this is the manual step (see RELEASE_PIPELINE.md).
set -euo pipefail

cd "$(dirname "$0")/.."

marketing_version() {
  # Read MARKETING_VERSION from the XcodeGen source of truth (project.yml).
  sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}.*/\1/p' \
    project.yml | head -1
}

build_number() {
  # A shallow clone (e.g. actions/checkout default fetch-depth: 1) yields a wrong, non-monotonic count,
  # and App Store Connect rejects a CFBundleVersion that isn't strictly greater than the last upload.
  # Fail loudly rather than emit a bogus number; use full history (fetch-depth: 0) or pass BUILD=<n>.
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    echo "release_metadata.sh: shallow clone — commit-count build number is unreliable." >&2
    echo "  Fetch full history (git fetch --unshallow / fetch-depth: 0) or pass BUILD=<n>." >&2
    exit 1
  fi
  git rev-list --count HEAD
}

if [ "${1:-}" = "build-number" ]; then
  build_number
  exit 0
fi

VERSION="$(marketing_version)"
BUILD="$(build_number)"
COMMIT="$(git rev-parse --short HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "version: ${VERSION:-unknown}"
echo "build: ${BUILD}"
echo "commit: ${COMMIT}"
echo "branch: ${BRANCH}"
echo "date: ${DATE}"
echo ""
echo "Release notes:"

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "${LAST_TAG}" ]; then
  RANGE="${LAST_TAG}..HEAD"
else
  RANGE="-20"
fi
# Commit subjects only (no bodies), so no sensitive detail leaks into release notes.
git log --no-merges --pretty=format:'- %s' "${RANGE}" | sed '/^- $/d'
echo ""
