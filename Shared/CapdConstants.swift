import Foundation

public enum CapdConstants {
  public static let appBundleID = "net.snix.capd"
  public static let helperLabel = "net.snix.capd.helper"
  public static let machServiceName = helperLabel

  public static let helperProtocolVersion = 1
  public static let helperPingResponse = "capd-helper/v\(helperProtocolVersion)"

  public static let defaultsChargeLimitKey = "chargeLimitPercent"
  public static let defaultsColoredIconKey = "coloredMenuBarIcon"
  public static let helperPersistedLimitKey = "persistedChargeLimitPercent"
  public static let defaultChargeLimitPercent = 80

  public static let minChargeLimitPercent = 30
  public static let maxChargeLimitPercent = 100

  public static func clampLimit(_ value: Int) -> Int {
    min(max(value, minChargeLimitPercent), maxChargeLimitPercent)
  }
}
