import Foundation

public enum CapdConstants {
  public static let appBundleID = "com.example.capd"
  public static let helperLabel = "com.example.capd.helper"
  public static let machServiceName = "com.example.capd.helper"

  public static let defaultsChargeLimitKey = "chargeLimitPercent"
  public static let defaultsColoredIconKey = "coloredMenuBarIcon"
  public static let defaultChargeLimitPercent = 80

  public static let minChargeLimitPercent = 30
  public static let maxChargeLimitPercent = 100

  public static func clampLimit(_ value: Int) -> Int {
    min(max(value, minChargeLimitPercent), maxChargeLimitPercent)
  }
}
