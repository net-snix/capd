import Foundation
import Security
import os.log

final class XPCCallerValidator {
  private let logger = Logger(subsystem: CapdConstants.helperLabel, category: "xpc")
  private let requirement: SecRequirement?

  init() {
    requirement = Self.makeAuthorizedClientRequirement()
  }

  func isAuthorized(_ connection: NSXPCConnection) -> Bool {
    guard let requirement else {
      logger.error("Rejecting XPC client: SMAuthorizedClients requirement is unavailable.")
      return false
    }

    let pid = connection.processIdentifier
    guard pid > 0 else {
      logger.error("Rejecting XPC client: invalid process identifier \(pid, privacy: .public).")
      return false
    }

    let attributes: [CFString: Any] = [kSecGuestAttributePid: NSNumber(value: pid)]
    var code: SecCode?
    let copyStatus = SecCodeCopyGuestWithAttributes(
      nil,
      attributes as CFDictionary,
      SecCSFlags(),
      &code
    )

    guard copyStatus == errSecSuccess, let code else {
      logger.error("Rejecting XPC client PID \(pid, privacy: .public): could not load signing info (\(Self.statusText(copyStatus), privacy: .public)).")
      return false
    }

    let checkStatus = SecCodeCheckValidity(code, SecCSFlags(), requirement)
    guard checkStatus == errSecSuccess else {
      logger.error("Rejecting XPC client PID \(pid, privacy: .public): code signing check failed (\(Self.statusText(checkStatus), privacy: .public)).")
      return false
    }

    return true
  }

  private static func makeAuthorizedClientRequirement() -> SecRequirement? {
    guard let clients = Bundle.main.object(forInfoDictionaryKey: "SMAuthorizedClients") as? [String],
          let requirementString = clients.first,
          !requirementString.isEmpty else {
      return nil
    }

    var requirement: SecRequirement?
    let status = SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement)
    guard status == errSecSuccess else { return nil }
    return requirement
  }

  private static func statusText(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
      return "\(message) (\(status))"
    }
    return "OSStatus \(status)"
  }
}
