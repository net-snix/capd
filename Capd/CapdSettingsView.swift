import ServiceManagement
import SwiftUI

struct CapdSettingsView: View {
  @EnvironmentObject private var helperManager: HelperManager

  @AppStorage(CapdConstants.defaultsColoredIconKey)
  private var coloredMenuBarIcon: Bool = false

  @State private var launchAtLoginEnabled: Bool = false
  @State private var launchAtLoginError: String?

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { launchAtLoginEnabled },
      set: { newValue in
        launchAtLoginEnabled = newValue
        setLaunchAtLogin(newValue)
      }
    )
  }

  private var helperButtonTitle: String {
    helperManager.isHelperReachable ? "Reinstall Helper" : "Install Helper"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings").font(.headline)

      Toggle("Launch at Login", isOn: launchAtLoginBinding)
        .toggleStyle(.switch)
        .tint(.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)

      Toggle("Colored menu bar icon", isOn: $coloredMenuBarIcon)
        .toggleStyle(.switch)
        .tint(.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(helperButtonTitle) {
        helperManager.installHelper()
      }
      .buttonStyle(.borderedProminent)

      if let launchAtLoginError {
        Text(launchAtLoginError)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if helperManager.statusText != "Helper reachable" {
        Text(helperManager.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(width: 280)
    .tint(.accentColor)
    .onAppear {
      syncLaunchAtLoginState()
    }
  }

  private func syncLaunchAtLoginState() {
    launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLoginError = nil
      syncLaunchAtLoginState()
    } catch {
      launchAtLoginError = "Launch at login failed: \(error.localizedDescription)"
      syncLaunchAtLoginState()
    }
  }
}
