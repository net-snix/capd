import Foundation

final class HelperClient {
  private var connection: NSXPCConnection?

  func ping(completion: @escaping (Result<String, Error>) -> Void) {
    guard let proxy = remoteProxy(errorHandler: { completion(.failure($0)) }) else { return }
    proxy.ping { value in
      completion(.success(value))
    }
  }

  func setChargeLimit(_ percent: Int, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let proxy = remoteProxy(errorHandler: { completion(.failure($0)) }) else { return }
    proxy.setChargeLimit(percent) { error in
      if let error {
        completion(.failure(error))
      } else {
        completion(.success(()))
      }
    }
  }

  func clearChargeLimit(completion: @escaping (Result<Void, Error>) -> Void) {
    guard let proxy = remoteProxy(errorHandler: { completion(.failure($0)) }) else { return }
    proxy.clearChargeLimit { error in
      if let error {
        completion(.failure(error))
      } else {
        completion(.success(()))
      }
    }
  }

  func invalidate() {
    connection?.invalidate()
    connection = nil
  }

  private func remoteProxy(errorHandler: @escaping (Error) -> Void) -> CapdHelperProtocol? {
    let conn = connection ?? makeConnection()
    connection = conn
    return conn.remoteObjectProxyWithErrorHandler { error in
      self.invalidate()
      errorHandler(error)
    } as? CapdHelperProtocol
  }

  private func makeConnection() -> NSXPCConnection {
    let conn = NSXPCConnection(machServiceName: CapdConstants.machServiceName, options: .privileged)
    conn.remoteObjectInterface = NSXPCInterface(with: CapdHelperProtocol.self)
    conn.interruptionHandler = { [weak self] in
      self?.connection = nil
    }
    conn.invalidationHandler = { [weak self] in
      self?.connection = nil
    }
    conn.resume()
    return conn
  }
}
