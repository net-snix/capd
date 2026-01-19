# Capd

Capd is a macOS menu bar app that caps battery charging to a user-set percentage (e.g. 80%) when plugged into external power.

## What’s scaffolded
- XcodeGen project: `capd/project.yml` (generates `capd/Capd.xcodeproj`)
- Menu bar UI: slider + % text field (persisted via `UserDefaults`)
- Battery monitor: IOKit Power Sources → status text
- Privileged helper wiring: SMJobBless + launchd plist + XPC protocol
- Helper behavior: BCLM-based SMC write; falls back to charging control keys (CH0C or CHTE on Tahoe)
Internal developer notes are intentionally omitted from the public repo.

## Generate + open
- Generate project: `cd capd && xcodegen generate`
- Open: `open capd/Capd.xcodeproj`

## Build (unsigned)
- `cd capd && ./Scripts/build-unsigned.sh`

## Configure bundle IDs (if you want)
Current defaults (edit `capd/project.yml` + regenerate):
- App: `com.espenmac.capd`
- Helper label/service: `com.espenmac.capd.helper`

## SMJobBless notes
SMJobBless requires proper signing (same team) to actually install the helper. Expect the “Install Helper” button to fail until:
- You set a real signing team in Xcode, and
- `SMPrivilegedExecutables` (app) and `SMAuthorizedClients` (helper) requirement strings match your signing.
