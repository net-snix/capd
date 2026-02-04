# Helper + SMC details

## ChargeLimiter
- Primary path: write SMC key `BCLM` with percent (1 or 2 bytes) via `SMCConnection`.
- Fallback path (if `BCLM` unsupported): use charging control keys `CHTE` / `CH0C`.
- Hysteresis: 3% (enable below `limit-3`, disable above `limit`).
- `setLimit` calls:
  - Reads battery state via `IOKit.ps`.
  - Updates MagSafe LED (key `ACLC`) when supported.

## Monitoring cadence
- Helper starts a 60s repeating timer only when using charging-control keys.
- Each tick calls `ChargeLimiter.setLimit(limit)` (battery read + possible SMC write).
- Timer stops when limit cleared or BCLM mode is detected.

## XPC + SMC
- App ↔ helper uses `NSXPCConnection` to privileged Mach service.
- Helper uses `IOServiceOpen` + `IOConnectCallMethod` to AppleSMC.
