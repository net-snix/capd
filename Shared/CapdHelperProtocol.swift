import Foundation

@objc public protocol CapdHelperProtocol {
  func ping(withReply reply: @escaping (String) -> Void)
  func setChargeLimit(_ percent: Int, withReply reply: @escaping (NSError?) -> Void)
  func clearChargeLimit(withReply reply: @escaping (NSError?) -> Void)
}

public enum CapdHelperErrorCode: Int {
  case notImplemented = 1
  case invalidArgument = 2
  case notSupported = 3
  case smcFailure = 4
}

public func makeCapdHelperError(_ code: CapdHelperErrorCode, description: String) -> NSError {
  NSError(
    domain: CapdConstants.helperLabel,
    code: code.rawValue,
    userInfo: [NSLocalizedDescriptionKey: description]
  )
}
