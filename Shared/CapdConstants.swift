import Foundation

public enum CapdConstants {
  public static let appBundleID = "com.espenmac.capd"
  public static let helperLabel = "com.espenmac.capd.helper"
  public static let machServiceName = "com.espenmac.capd.helper"

  public static let defaultsChargeLimitKey = "chargeLimitPercent"
  public static let defaultChargeLimitPercent = 80

  public static let minChargeLimitPercent = 30
  public static let maxChargeLimitPercent = 100

  public static func clampLimit(_ value: Int) -> Int {
    min(max(value, minChargeLimitPercent), maxChargeLimitPercent)
  }
}
