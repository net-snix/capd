# Key files map

App:
- `Capd/CapdApp.swift` — app entrypoint, MenuBarExtra.
- `Capd/Battery/BatteryMonitor.swift` — battery state via IOKit notifications.
- `Capd/CapdMenuView.swift` — slider + onChange triggers helper apply.
- `Capd/MenuBarIconView.swift` — draws ring icon from snapshot.
- `Capd/Helper/HelperManager.swift` — debounced requests + helper reachability.
- `Capd/Helper/HelperClient.swift` — NSXPCConnection to helper.
- `Capd/Helper/HelperInstaller.swift` — SMJobBless helper install.
- `Capd/Util/Debouncer.swift` — debounce helper calls.

Helper:
- `capd-helper/CapdHelper.swift` — XPC service, SMC writes, 30s monitor timer.
- `capd-helper/SMCChargeLimiter.swift` — SMC IO, BCLM/CHTE/CH0C, hysteresis.
- `capd-helper/HelperXPCDelegate.swift` + `main.swift` — NSXPCListener setup.

Shared:
- `Shared/CapdConstants.swift` — config + bounds.
- `Shared/CapdHelperProtocol.swift` — XPC protocol + error helper.

