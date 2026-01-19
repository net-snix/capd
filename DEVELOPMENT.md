# Capd — Development Notes

## Project generation
- Generate Xcode project: `cd capd && xcodegen generate`
- Open: `open capd/Capd.xcodeproj`

## Running the menu bar app
The app is a `MenuBarExtra` SwiftUI app with `LSUIElement = true` (no Dock icon).

## Privileged helper (SMJobBless) checklist
The helper install (“Install Helper” button) will only work once you have proper code signing set up.

0) Ensure you have a valid code signing identity:
- `security find-identity -v -p codesigning`
- If it shows `0 valid identities found`, add an Apple ID in Xcode → Settings → Accounts and create an “Apple Development” certificate (Manage Certificates…).

1) Set the same signing team for both targets:
- `Capd` (app)
- `capd-helper` (tool)

2) Ensure bundle IDs/labels match:
- App bundle id: `com.espenmac.capd`
- Helper label + Mach service name: `com.espenmac.capd.helper`

3) Requirement strings must match your actual signatures:
- App `Info.plist` key `SMPrivilegedExecutables` must contain a requirement satisfied by the signed helper.
- Helper `Info.plist` key `SMAuthorizedClients` must contain a requirement satisfied by the signed app.

The scaffold uses a permissive default requirement (`identifier "…" and anchor apple generic`) so you can tighten it later.

Troubleshooting:
- If SMJobBless fails and the system log shows `smd: Helper has no embedded Info.plist`, ensure the helper target build setting `CREATE_INFOPLIST_SECTION_IN_BINARY = YES` (this repo sets it via `capd/project.yml`).

## XPC notes
The app connects with:
- `NSXPCConnection(machServiceName: CapdConstants.machServiceName, options: .privileged)`

The helper listens on:
- `NSXPCListener(machServiceName: CapdConstants.machServiceName)`

## Charge limiting implementation status
`capd-helper` tries a BCLM-based SMC charge limit first. If BCLM is not supported, it attempts charging control via CH0C (pre-Tahoe) or CHTE (Tahoe) with hysteresis. If neither is available, it reports "not supported."

## SMC probe tool
To probe SMC key availability and formats on a machine:
- `capd/Scripts/run-smc-probe.sh`
- Optional: pass custom keys, e.g. `capd/Scripts/run-smc-probe.sh CHTE CH0C CHIE CH0J`
