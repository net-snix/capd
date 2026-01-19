import Foundation

final class HelperXPCDelegate: NSObject, NSXPCListenerDelegate {
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: CapdHelperProtocol.self)
    newConnection.exportedObject = CapdHelper()
    newConnection.resume()
    return true
  }
}

