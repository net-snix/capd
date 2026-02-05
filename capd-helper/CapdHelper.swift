import Foundation
import IOKit.ps
import os.log

final class CapdHelper: NSObject, CapdHelperProtocol {
  private let logger = Logger(subsystem: CapdConstants.helperLabel, category: "helper")
  private let limiter = ChargeLimiter()
  private let workQueue = DispatchQueue(label: "\(CapdConstants.helperLabel).work")
  private let defaults = UserDefaults(suiteName: CapdConstants.helperLabel) ?? .standard
  private var monitoredLimitPercent: Int?
  private var powerSourceRunLoopSource: CFRunLoopSource?
  private var powerSourceContext: UnsafeMutableRawPointer?

  override init() {
    super.init()
    restorePersistedLimitIfNeeded()
  }

  func ping(withReply reply: @escaping (String) -> Void) {
    reply(CapdConstants.helperPingResponse)
  }

  func setChargeLimit(_ percent: Int, withReply reply: @escaping (NSError?) -> Void) {
    let clamped = CapdConstants.clampLimit(percent)
    logger.info("setChargeLimit requested: \(clamped, privacy: .public)")
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        let mode = try self.limiter.setLimit(clamped)
        switch mode {
        case .bclm:
          self.stopMonitoring()
        case .chargingControl:
          self.startMonitoring(limitPercent: clamped)
        }
        self.persistedLimitPercent = clamped
        reply(nil)
      } catch let error as ChargeLimiterError {
        self.logger.error("setChargeLimit failed: \(error.localizedDescription, privacy: .public)")
        reply(makeCapdHelperError(error.code, description: error.localizedDescription))
      } catch {
        let message = "SMC error: \(error.localizedDescription)"
        self.logger.error("\(message, privacy: .public)")
        reply(makeCapdHelperError(.smcFailure, description: message))
      }
    }
  }

  func clearChargeLimit(withReply reply: @escaping (NSError?) -> Void) {
    logger.info("clearChargeLimit requested")
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.limiter.clearLimit()
        self.stopMonitoring()
        self.persistedLimitPercent = nil
        reply(nil)
      } catch let error as ChargeLimiterError {
        self.logger.error("clearChargeLimit failed: \(error.localizedDescription, privacy: .public)")
        reply(makeCapdHelperError(error.code, description: error.localizedDescription))
      } catch {
        let message = "SMC error: \(error.localizedDescription)"
        self.logger.error("\(message, privacy: .public)")
        reply(makeCapdHelperError(.smcFailure, description: message))
      }
    }
  }

  private func startMonitoring(limitPercent: Int) {
    monitoredLimitPercent = limitPercent

    startPowerSourceMonitoring()
  }

  private func stopMonitoring() {
    monitoredLimitPercent = nil
    stopPowerSourceMonitoring()
  }

  private func monitorTick() {
    guard let limit = monitoredLimitPercent else { return }
    do {
      let mode = try limiter.setLimit(limit)
      if mode == .bclm {
        stopMonitoring()
      }
    } catch {
      logger.error("monitor tick failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func startPowerSourceMonitoring() {
    guard powerSourceRunLoopSource == nil else { return }
    let context = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
    guard let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let helper = Unmanaged<CapdHelper>.fromOpaque(context).takeUnretainedValue()
      helper.workQueue.async {
        helper.monitorTick()
      }
    }, context)?.takeRetainedValue() else {
      Unmanaged<CapdHelper>.fromOpaque(context).release()
      return
    }

    powerSourceContext = context
    powerSourceRunLoopSource = source
    performOnMain {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
  }

  private func stopPowerSourceMonitoring() {
    if let source = powerSourceRunLoopSource {
      performOnMain {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
      }
      powerSourceRunLoopSource = nil
    }

    if let context = powerSourceContext {
      Unmanaged<CapdHelper>.fromOpaque(context).release()
      powerSourceContext = nil
    }
  }

  private func performOnMain(_ block: () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.sync(execute: block)
    }
  }

  private var persistedLimitPercent: Int? {
    get {
      guard defaults.object(forKey: CapdConstants.helperPersistedLimitKey) != nil else { return nil }
      return defaults.integer(forKey: CapdConstants.helperPersistedLimitKey)
    }
    set {
      if let newValue {
        defaults.set(newValue, forKey: CapdConstants.helperPersistedLimitKey)
      } else {
        defaults.removeObject(forKey: CapdConstants.helperPersistedLimitKey)
      }
    }
  }

  private func restorePersistedLimitIfNeeded() {
    guard let storedLimit = persistedLimitPercent else { return }
    let limit = CapdConstants.clampLimit(storedLimit)

    workQueue.async { [weak self] in
      guard let self else { return }

      do {
        let mode = try self.limiter.setLimit(limit)
        switch mode {
        case .bclm:
          self.stopMonitoring()
        case .chargingControl:
          self.startMonitoring(limitPercent: limit)
        }
        self.logger.info("Restored persisted charge limit: \(limit, privacy: .public)")
      } catch {
        self.logger.error("Failed restoring persisted charge limit: \(error.localizedDescription, privacy: .public)")
        self.persistedLimitPercent = nil
      }
    }
  }
}
