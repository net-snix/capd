import Foundation
import os.log

final class HelperXPCDelegate: NSObject, NSXPCListenerDelegate {
  private let logger = Logger(subsystem: CapdConstants.helperLabel, category: "xpc")
  private let helper = CapdHelper()
  private let callerValidator = XPCCallerValidator()

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
    guard callerValidator.isAuthorized(newConnection) else {
      logger.error("Rejected unauthorized XPC connection from PID \(newConnection.processIdentifier, privacy: .public).")
      return false
    }

    newConnection.exportedInterface = NSXPCInterface(with: CapdHelperProtocol.self)
    newConnection.exportedObject = helper
    newConnection.resume()
    return true
  }
}
