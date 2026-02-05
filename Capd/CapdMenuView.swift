import AppKit
import SwiftUI

struct CapdMenuView: View {
  @EnvironmentObject private var batteryMonitor: BatteryMonitor
  @EnvironmentObject private var helperManager: HelperManager

  @AppStorage(CapdConstants.defaultsChargeLimitKey)
  private var limitPercent: Int = CapdConstants.defaultChargeLimitPercent

  private var limitPercentBinding: Binding<Int> {
    Binding(
      get: { limitPercent },
      set: { updateLimitPercent($0) }
    )
  }

  private var limitBindingForSlider: Binding<Double> {
    Binding(
      get: { Double(limitPercent) },
      set: { updateLimitPercent(Int($0.rounded())) }
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
        TextField("", value: limitPercentBinding, format: .number)
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
        if let helperStatusText = helperManager.menuStatusText {
          Text(helperStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .frame(width: 280)
    .onAppear {
      let clamped = CapdConstants.clampLimit(limitPercent)
      if clamped != limitPercent {
        limitPercent = clamped
      }
      helperManager.requestApply(limitPercent: clamped)
    }
  }

  private func updateLimitPercent(_ newValue: Int) {
    let clamped = CapdConstants.clampLimit(newValue)
    if clamped != limitPercent {
      limitPercent = clamped
    }
    helperManager.requestApply(limitPercent: clamped)
  }
}
