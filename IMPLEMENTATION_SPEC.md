# Capd — Implementation Spec (macOS menu bar)

## 1) Problem / Goal
Capd is a lightweight macOS menu bar app that lets the user set a maximum battery charge percentage (e.g. 80%). When the Mac is connected to external power and the battery reaches the configured limit, Capd prevents further charging so the system runs from the power adapter (similar to behavior at 100%).

## 2) Scope
### Must-have
- Menu bar app with a popover UI.
- One charge limit value (`0–100`, practical minimum recommended `40–50`).
- Slider + numeric text input bound to the same value.
- Persist the configured limit and re-apply on launch.
- Monitor battery state (percentage + charging + AC status) and show current status text in the popover.

### Nice-to-have (optional)
- “Start at login” toggle.
- “Temporarily disable” / “Set to 100%” quick action.
- Small status line in menu bar title (e.g. `80% ⏸︎`), user-configurable.
- Basic diagnostics export (log snippet).

### Non-goals
- App Store distribution (charge control generally requires privileged/private mechanisms).
- Supporting non-portable/unstable kernel extensions.

## 3) Key Constraint (Reality Check)
Apple does not provide a stable public API to set an arbitrary “charge limit.” Achieving this typically requires interacting with the SMC / power management internals via IOKit, which often requires **root privileges** and may vary by model/macOS version.

Capd should be designed with:
- A **best-effort** “apply limit” path where supported.
- Clear user messaging when the system model does not support the required control.

## 4) UX / UI Spec (Popover)
Popover content (single view):
- Title: `Capd`
- Row: `Limit` label + numeric text field (percentage)
- Slider: range `50…100` (configurable later), step `1`
- Status text (read-only): e.g. `Battery 76% • Plugged In • Charging`

Interaction rules:
- Slider movement updates text field live.
- Text field accepts integers; invalid input is rejected or clamped:
  - Empty → revert to last valid value on blur/enter.
  - `<0` → clamp to `0`
  - `>100` → clamp to `100`
- Setting changes apply with a short debounce (e.g. `300–800ms`) to avoid spamming the helper.

## 5) High-Level Architecture
Two-process design:
1) **Capd.app (unprivileged)** — menu bar UI, state monitoring, persistence.
2) **capd-helper (privileged)** — applies/clears charge limit using SMC/IOKit.

Communication:
- `Capd.app` ↔ `capd-helper` via XPC (recommended) or a minimal CLI wrapper invoked through the helper.

Why a helper:
- Writing to SMC / power management controls is typically not permitted to unprivileged apps.
- A helper allows least-privilege UI + tightly-scoped privileged operations.

## 6) Battery State Monitoring (UI process)
Primary API: IOKit Power Sources (no polling needed).
- Use `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, and `IOPSGetPowerSourceDescription` to read:
  - `kIOPSCurrentCapacityKey` / `kIOPSMaxCapacityKey` → percent
  - `kIOPSPowerSourceStateKey` → AC vs Battery
  - `kIOPSIsChargingKey` → charging boolean
- Subscribe to updates with `IOPSNotificationCreateRunLoopSource` and update an observable model.

Model in app:
- `BatterySnapshot`:
  - `percentage: Int`
  - `isPluggedIn: Bool`
  - `isCharging: Bool`
  - `timestamp: Date`

UI displays the snapshot; the app also uses it to decide when to re-apply the limit (e.g. after wake or AC changes).

## 7) Charge Limiting Strategy (Helper process)
### Preferred: SMC “max charge” (BCLM)
Many MacBook models expose an SMC key commonly referred to as **BCLM** (“Battery Charge Level Max”) that caps the maximum charge percentage. If available, this is the most direct way to implement “stop charging at X%”.

Helper responsibilities:
- Detect whether the platform exposes the necessary SMC key(s).
- Set maximum charge to `limitPercent` (e.g. 80).
- Clear/restore to system default (typically `100`) when user sets limit to `100` or presses “Disable”.

### Alternative: “charging enabled” gating + hysteresis
If a max-cap is unavailable but a “charging enabled” control exists, implement:
- Disable charging when `percentage >= limitPercent`.
- Re-enable charging when `percentage <= limitPercent - hysteresis` (e.g. `5`).

This prevents rapid toggling when the battery hovers around the threshold.

### Fallback: monitor-only mode
If neither control is supported:
- Capd still shows battery status + configured limit.
- “Apply limit” calls return an explanatory error (e.g. “Unsupported on this Mac / macOS version”).

## 8) Privileged Helper Implementation
### Installation
Recommended: `SMJobBless` (privileged helper tool) installed from the app bundle.
- Prompts once for admin authorization.
- Ensures only the signed Capd app can install/communicate with the helper.

### XPC surface area (minimal)
Define a single XPC protocol with strict validation:
- `setChargeLimit(percent: Int) -> Result`
- `clearChargeLimit() -> Result`
- `getStatus() -> HelperStatus` (optional)

Validation rules in helper:
- Clamp `percent` to `0…100`.
- Treat `>= 100` as “clear/restore default”.
- Reject non-integer / out-of-range at the interface boundary.

### Observability
Use `os_log` (separate subsystem/category) in both app and helper:
- App: user changes, state updates, apply attempts.
- Helper: install events, detected capabilities, successful/failed SMC writes.

## 9) Persistence
Store user configuration in `UserDefaults` (app container):
- `chargeLimitPercent: Int` default `80`
- (optional) `launchAtLogin: Bool` default `false`

On launch:
1) Read persisted limit.
2) Start battery monitor.
3) Apply limit once helper is reachable.

On wake / AC change:
- Re-apply the current limit (idempotent).

## 10) Failure Modes & User Messaging
Common issues:
- Helper not installed / authorization denied.
- Unsupported model/macOS (no known controls).
- SMC operation fails (permissions, OS update change, hardware).

UI behavior:
- Keep the slider editable (user can still set preference).
- Show a single-line status:
  - `Applied (80%)`
  - `Needs admin permission`
  - `Unsupported on this Mac`
  - `Failed to apply (see logs)`

## 11) Build/Tech Choices
- Language: Swift
- UI: SwiftUI popover hosted from NSStatusItem (AppKit bridge)
- Battery API: IOKit (Power Sources)
- Helper: SMJobBless + XPC
- Target OS: macOS 13+ recommended (modern login item APIs), macOS 12+ possible with extra work

## 12) Implementation Milestones
1) Menu bar + popover UI with slider/text field; persist to `UserDefaults`.
2) Battery monitor model using IOKit; show live status.
3) Helper scaffolding with XPC + SMJobBless install flow; no-op “apply” calls.
4) Implement capability detection + apply/clear in helper (SMC/BCLM or gating).
5) Add debounce + idempotent re-apply on wake/AC changes; tighten error messaging.

## 13) Risk Register
- **Compatibility risk:** charge control is not a stable public API; may break across macOS releases.
- **Privilege risk:** requires admin authorization and a privileged helper; not App Store friendly.
- **Hardware variance:** different Mac models expose different keys/controls.
- **Safety risk:** incorrect SMC writes can behave unpredictably; strict validation + narrow helper scope is mandatory.

