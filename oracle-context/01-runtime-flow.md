# Runtime flow overview

## App process (`Capd`)
- `CapdApp`: creates `BatteryMonitor` + `HelperManager` as `@StateObject`.
- Menu bar UI: `MenuBarExtra` hosts `CapdMenuView` and `MenuBarRingIconView`.

## Battery monitoring
- `BatteryMonitor` uses `IOPSNotificationCreateRunLoopSource` on main run loop.
- `updateSnapshot()` called on IOKit notifications; updates `snapshot` with percent + charging + plugged-in.

## UI-driven helper calls
- `CapdMenuView`:
  - `onAppear`: clamp limit + `HelperManager.requestApply(limit)`.
  - `onChange(of: limitPercent)`: clamp + `requestApply`.
- `HelperManager`:
  - `requestApply`: debounces 0.7s, calls helper XPC.
  - `refreshReachability`: ping helper on init.

## Helper process (`capd-helper`)
- XPC listener `HelperXPCDelegate` exports `CapdHelper`.
- `CapdHelper`:
  - `setChargeLimit`: workQueue → `ChargeLimiter.setLimit` + start monitor timer.
  - `clearChargeLimit`: workQueue → `ChargeLimiter.clearLimit` + stop timer.
  - Monitor timer: DispatchSourceTimer 60s repeating, only for charging-control fallback, calls `monitorTick`.
