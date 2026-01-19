import SwiftUI
import os.log

@main
struct CapdApp: App {
  @StateObject private var batteryMonitor = BatteryMonitor()
  @StateObject private var helperManager = HelperManager()

  private let logger = Logger(subsystem: CapdConstants.appBundleID, category: "app")

  init() {
    logger.info("Capd launched")
    print("Capd launched")
  }

  var body: some Scene {
    MenuBarExtra {
      CapdMenuView()
        .environmentObject(batteryMonitor)
        .environmentObject(helperManager)
    } label: {
      MenuBarRingIconView()
        .environmentObject(batteryMonitor)
    }
    .menuBarExtraStyle(.window)
  }
}
