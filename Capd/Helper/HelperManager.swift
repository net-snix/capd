import Foundation

private enum HelperStatus: Equatable {
  case notInstalled
  case installPrompt
  case reachable
  case applying(Int)
  case outdated(received: String)
  case error(String)

  var text: String {
    switch self {
    case .notInstalled:
      return "Helper not installed"
    case .installPrompt:
      return "Helper not installed (click Install Helper)"
    case .reachable:
      return "Helper reachable"
    case .applying(let limit):
      return "Applying \(limit)%…"
    case .outdated(let received):
      return "Helper update required (protocol mismatch: \(received))"
    case .error(let message):
      return message
    }
  }

  var isReachable: Bool {
    switch self {
    case .reachable, .applying:
      return true
    default:
      return false
    }
  }

  var menuText: String? {
    guard !isReachable else { return nil }
    switch self {
    case .outdated:
      return "Helper update required"
    case .error(let message):
      return message
    default:
      return "Helper not installed"
    }
  }

  var shouldShowStatusMessage: Bool {
    self != .reachable
  }
}

@MainActor
final class HelperManager: ObservableObject {
  @Published private var status: HelperStatus = .notInstalled

  var statusText: String { status.text }
  var isHelperReachable: Bool { status.isReachable }
  var menuStatusText: String? { status.menuText }
  var shouldShowStatusMessage: Bool { status.shouldShowStatusMessage }

  private let installer = HelperInstaller()
  private let client = HelperClient()
  private let debouncer = Debouncer(delay: 0.7)

  private var lastRequestedLimitPercent: Int?

  init() {
    refreshReachability()
  }

  func installHelper() {
    do {
      try installer.bless()
      refreshReachability { [weak self] reachable in
        guard let self else { return }
        if reachable, let pending = self.lastRequestedLimitPercent {
          self.requestApply(limitPercent: pending)
        }
      }
    } catch {
      status = .error(error.localizedDescription)
    }
  }

  func requestApply(limitPercent: Int) {
    let clamped = CapdConstants.clampLimit(limitPercent)
    lastRequestedLimitPercent = clamped

    guard isHelperReachable else {
      if case .outdated = status {
        return
      }
      status = .installPrompt
      return
    }

    debouncer.schedule { [weak self] in
      self?.apply(limitPercent: clamped)
    }
  }

  func refreshReachability(completion: ((Bool) -> Void)? = nil) {
    client.ping { result in
      Task { @MainActor in
        switch result {
        case .success(let value):
          guard value == CapdConstants.helperPingResponse else {
            self.status = .outdated(received: value)
            completion?(false)
            return
          }
          self.status = .reachable
          completion?(true)
        case .failure:
          self.status = .notInstalled
          completion?(false)
        }
      }
    }
  }

  private func apply(limitPercent: Int) {
    status = .applying(limitPercent)

    if limitPercent >= 100 {
      client.clearChargeLimit { result in
        Task { @MainActor in
          switch result {
          case .success:
            self.status = .reachable
          case .failure(let error):
            self.status = .error(error.localizedDescription)
          }
        }
      }
    } else {
      client.setChargeLimit(limitPercent) { result in
        Task { @MainActor in
          switch result {
          case .success:
            self.status = .reachable
          case .failure(let error):
            self.status = .error(error.localizedDescription)
          }
        }
      }
    }
  }
}
