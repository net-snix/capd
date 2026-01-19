import Foundation
import Security
import ServiceManagement

enum HelperInstallerError: LocalizedError {
  case authorizationFailed(OSStatus)
  case authorizationRightsFailed(OSStatus)
  case blessFailed(Error)
  case blessFailedUnknown

  var errorDescription: String? {
    switch self {
    case .authorizationFailed(let status):
      return "Authorization failed (\(status))"
    case .authorizationRightsFailed(let status):
      return "Authorization rights request failed (\(status))"
    case .blessFailed(let error):
      let nsError = error as NSError
      if nsError.domain == "CFErrorDomainLaunchd", nsError.code == 8 {
        return """
SMJobBless failed (launchd error 8). This usually means the privileged helper did not pass validation.
Check that you have a valid Apple code signing identity and both `Capd` and `capd-helper` are signed.
"""
      }
      return "SMJobBless failed: \(error.localizedDescription)"
    case .blessFailedUnknown:
      return "SMJobBless failed (unknown error)"
    }
  }
}

final class HelperInstaller {
  func bless() throws {
    var authRef: AuthorizationRef?
    let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
    let status = AuthorizationCreate(nil, nil, flags, &authRef)

    guard status == errAuthorizationSuccess, let authRef else {
      throw HelperInstallerError.authorizationFailed(status)
    }

    defer { AuthorizationFree(authRef, []) }

    let rightsStatus: OSStatus = kSMRightBlessPrivilegedHelper.withCString { namePtr in
      var authItem = AuthorizationItem(
        name: namePtr,
        valueLength: 0,
        value: nil,
        flags: 0
      )
      return withUnsafeMutablePointer(to: &authItem) { authItemPtr in
        var authRights = AuthorizationRights(count: 1, items: authItemPtr)
        return AuthorizationCopyRights(authRef, &authRights, nil, flags, nil)
      }
    }
    guard rightsStatus == errAuthorizationSuccess else {
      throw HelperInstallerError.authorizationRightsFailed(rightsStatus)
    }

    var error: Unmanaged<CFError>?
    let ok = SMJobBless(kSMDomainSystemLaunchd, CapdConstants.helperLabel as CFString, authRef, &error)
    if ok { return }

    if let error {
      throw HelperInstallerError.blessFailed(error.takeRetainedValue() as Error)
    }
    throw HelperInstallerError.blessFailedUnknown
  }
}
