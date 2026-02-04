import AppKit
import SwiftUI

struct CapdMenuView: View {
  @EnvironmentObject private var batteryMonitor: BatteryMonitor
  @EnvironmentObject private var helperManager: HelperManager

  @AppStorage(CapdConstants.defaultsChargeLimitKey)
  private var limitPercent: Int = CapdConstants.defaultChargeLimitPercent

  private var limitBindingForSlider: Binding<Double> {
    Binding(
      get: { Double(limitPercent) },
      set: { limitPercent = Int($0.rounded()) }
    )
  }

  private var powerSourceText: String? {
    guard limitPercent < CapdConstants.maxChargeLimitPercent else { return nil }
    let snapshot = batteryMonitor.snapshot
    return snapshot.isPluggedIn ? "Power Source: Power Adapter" : "Power Source: Battery"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Capd").font(.headline)
        Spacer()
        Menu {
          Button("Settings") {
            SettingsWindowController.show(helperManager: helperManager)
          }
          Divider()
          Button("Quit Capd") {
            NSApplication.shared.terminate(nil)
          }
        } label: {
          Image(systemName: "line.3.horizontal")
        }
      }

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
        if !helperManager.isHelperReachable {
          Text("Helper not installed")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .frame(width: 280)
    .onAppear {
      limitPercent = CapdConstants.clampLimit(limitPercent)
      helperManager.requestApply(limitPercent: limitPercent)
    }
    .onChange(of: limitPercent) { newValue in
      let clamped = CapdConstants.clampLimit(newValue)
      if clamped != newValue {
        limitPercent = clamped
        return
      }
      helperManager.requestApply(limitPercent: clamped)
    }
  }
}
