import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
  static let shared = SettingsWindowController()

  private var hostingController: NSHostingController<AnyView>?

  static func show(helperManager: HelperManager) {
    shared.showWindow(helperManager: helperManager)
  }

  private func showWindow(helperManager: HelperManager) {
    let rootView = CapdSettingsView()
      .environmentObject(helperManager)
    let anyView = AnyView(rootView)

    if let hostingController {
      hostingController.rootView = anyView
    } else {
      let hosting = NSHostingController(rootView: anyView)
      hostingController = hosting

      let window = NSWindow(contentViewController: hosting)
      window.styleMask = [.titled, .closable]
      window.title = "Settings"
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 280, height: 230))
      self.window = window
    }

    guard let window else { return }
    positionWindow(window)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func positionWindow(_ window: NSWindow) {
    if let screen = NSScreen.main?.visibleFrame {
      let origin = CGPoint(
        x: screen.midX - window.frame.width / 2,
        y: screen.midY - window.frame.height / 2
      )
      window.setFrameOrigin(origin)
    }
  }
}
