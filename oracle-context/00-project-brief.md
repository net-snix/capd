# Capd project brief

- Product: macOS menu bar app that limits battery charge to reduce long-term wear.
- Stack: Swift + SwiftUI, AppKit, IOKit, ServiceManagement (SMJobBless).
- App bundle: `Capd/` (menu bar UI + settings).
- Privileged helper: `capd-helper/` (SMC writes, runs via XPC/SMJobBless).
- Shared types/constants: `Shared/`.
- Project config: XcodeGen `project.yml` → generates `Capd.xcodeproj`.

## Build/run
- Generate project: `xcodegen generate` (from repo root).
- Open Xcode project: `Capd.xcodeproj`.
- Unsigned build script: `Scripts/build-unsigned.sh`.

## Goal for review
- Full review of performance implications and battery-health implications.
- Emphasis: background work, timers, polling, SMC IO frequency, menu bar rendering cost, XPC chatter.

