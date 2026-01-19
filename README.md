# Capd

Capd is a lightweight macOS menu bar app that limits battery charging to a chosen percentage to reduce long‑term battery wear.

## What’s scaffolded
- XcodeGen project: `capd/project.yml` (generates `capd/Capd.xcodeproj`)
- Menu bar UI: slider + % text field (persisted via `UserDefaults`)
- Battery monitor: IOKit Power Sources → status text
- Privileged helper wiring: SMJobBless + launchd plist + XPC protocol
- Helper behavior: BCLM-based SMC write; falls back to charging control keys (CH0C or CHTE on Tahoe)

Internal developer notes are intentionally omitted from the public repo.

## Requirements
- Xcode 15+
- XcodeGen (`brew install xcodegen`)

## Generate + open (required)
- Generate project: `cd capd && xcodegen generate`
- Open: `open capd/Capd.xcodeproj`

## Build (unsigned)
- `cd capd && ./Scripts/build-unsigned.sh`

## Configure bundle IDs (if you want)
Defaults are placeholders. Edit `capd/project.yml` and regenerate:
- App: `com.example.capd`
- Helper label/service: `com.example.capd.helper`

## SMJobBless notes
SMJobBless requires proper signing (same team) to actually install the helper. Expect the “Install Helper” button to fail until:
- You set a real signing team in Xcode, and
- `SMPrivilegedExecutables` (app) and `SMAuthorizedClients` (helper) requirement strings match your signing.
