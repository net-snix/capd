import Foundation

@MainActor
final class HelperManager: ObservableObject {
  @Published var statusText: String = "Helper not installed"
  @Published private(set) var isHelperReachable: Bool = false

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
      isHelperReachable = false
      statusText = error.localizedDescription
    }
  }

  func requestApply(limitPercent: Int) {
    let clamped = CapdConstants.clampLimit(limitPercent)
    lastRequestedLimitPercent = clamped

    guard isHelperReachable else {
      statusText = "Helper not installed (click Install Helper)"
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
        case .success:
          self.isHelperReachable = true
          if self.statusText == "Helper not installed" || self.statusText.hasPrefix("Helper not installed") {
            self.statusText = "Helper reachable"
          }
          completion?(true)
        case .failure:
          self.isHelperReachable = false
          if self.statusText == "Helper reachable" {
            self.statusText = "Helper not installed"
          }
          completion?(false)
        }
      }
    }
  }

  private func apply(limitPercent: Int) {
    statusText = "Applying \(limitPercent)%…"

    if limitPercent >= 100 {
      client.clearChargeLimit { result in
        Task { @MainActor in
          switch result {
          case .success:
            self.statusText = "Helper reachable"
          case .failure(let error):
            self.statusText = error.localizedDescription
          }
        }
      }
    } else {
      client.setChargeLimit(limitPercent) { result in
        Task { @MainActor in
          switch result {
          case .success:
            self.statusText = "Helper reachable"
          case .failure(let error):
            self.statusText = error.localizedDescription
          }
        }
      }
    }
  }
}
