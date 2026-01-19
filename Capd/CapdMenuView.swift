import ServiceManagement
import SwiftUI

struct CapdMenuView: View {
  @EnvironmentObject private var batteryMonitor: BatteryMonitor
  @EnvironmentObject private var helperManager: HelperManager

  @AppStorage(CapdConstants.defaultsChargeLimitKey)
  private var limitPercent: Int = CapdConstants.defaultChargeLimitPercent

  @State private var launchAtLoginEnabled: Bool = false
  @State private var launchAtLoginError: String?

  private var limitBindingForSlider: Binding<Double> {
    Binding(
      get: { Double(limitPercent) },
      set: { limitPercent = Int($0.rounded()) }
    )
  }

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

  private var powerSourceText: String? {
    guard limitPercent < CapdConstants.maxChargeLimitPercent else { return nil }
    let snapshot = batteryMonitor.snapshot
    guard snapshot.isPluggedIn, !snapshot.isCharging, snapshot.percentage >= limitPercent else { return nil }
    return "Power Source: Power Adapter"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Capd").font(.headline)

      HStack(spacing: 8) {
        Text("Limit")
        Spacer()
        TextField("", value: $limitPercent, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 64)
        Text("%").foregroundStyle(.secondary)
      }

      Slider(
        value: limitBindingForSlider,
        in: Double(CapdConstants.minChargeLimitPercent)...Double(CapdConstants.maxChargeLimitPercent),
        step: 1
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(batteryMonitor.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let powerSourceText {
          Text(powerSourceText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let launchAtLoginError {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(helperManager.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack {
        Button(helperButtonTitle) {
          helperManager.installHelper()
        }
      }

      Toggle("Launch at login", isOn: launchAtLoginBinding)
    }
    .padding(12)
    .frame(width: 280)
    .onAppear {
      limitPercent = CapdConstants.clampLimit(limitPercent)
      helperManager.requestApply(limitPercent: limitPercent)
      syncLaunchAtLoginState()
    }
    .onChange(of: limitPercent) { newValue in
      let clamped = CapdConstants.clampLimit(newValue)
      if clamped != newValue {
        limitPercent = clamped
        return
      }
      helperManager.requestApply(limitPercent: clamped)
    }
    .onChange(of: batteryMonitor.snapshot) { _ in
      guard limitPercent < CapdConstants.maxChargeLimitPercent else { return }
      helperManager.requestApply(limitPercent: limitPercent)
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
