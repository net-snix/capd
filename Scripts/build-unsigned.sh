#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT}"
xcodegen generate

xcodebuild \
  -project Capd.xcodeproj \
  -scheme Capd \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/capd-deriveddata \
  CODE_SIGNING_ALLOWED=NO \
  build
