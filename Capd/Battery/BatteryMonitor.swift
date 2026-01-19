import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
  var percentage: Int
  var isPluggedIn: Bool
  var isCharging: Bool

  static let unknown = BatterySnapshot(percentage: 0, isPluggedIn: false, isCharging: false)
}

final class BatteryMonitor: ObservableObject {
  @Published private(set) var snapshot: BatterySnapshot = .unknown

  private var runLoopSource: CFRunLoopSource?

  var statusText: String {
    let pluggedText = snapshot.isPluggedIn ? "Plugged In" : "On Battery"
    let chargingText = snapshot.isCharging ? "Charging" : "Not Charging"
    return "Battery \(snapshot.percentage)% • \(pluggedText) • \(chargingText)"
  }

  var menuBarSymbolName: String {
    if snapshot.isPluggedIn, snapshot.isCharging {
      return "battery.100.bolt"
    }
    return "battery.100"
  }

  init() {
    start()
  }

  deinit {
    stop()
  }

  func start() {
    guard runLoopSource == nil else { return }
    updateSnapshot()

    let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    guard let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
      monitor.updateSnapshot()
    }, context)?.takeRetainedValue() else {
      return
    }

    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    runLoopSource = nil
  }

  private func updateSnapshot() {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else {
      return
    }

    for ps in list {
      guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else {
        continue
      }

      guard let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
            let max = desc[kIOPSMaxCapacityKey as String] as? Int,
            max > 0
      else {
        continue
      }

      let percent = Int((Double(current) / Double(max) * 100.0).rounded())
      let state = desc[kIOPSPowerSourceStateKey as String] as? String
      let isPluggedIn = (state == kIOPSACPowerValue)
      let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false

      snapshot = BatterySnapshot(percentage: percent, isPluggedIn: isPluggedIn, isCharging: isCharging)
      return
    }
  }
}
