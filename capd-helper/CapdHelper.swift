import Foundation
import IOKit.ps
import os.log

final class CapdHelper: NSObject, CapdHelperProtocol {
  private let logger = Logger(subsystem: CapdConstants.helperLabel, category: "helper")
  private let limiter = ChargeLimiter()
  private let workQueue = DispatchQueue(label: "com.example.capd.helper.work")
  private var monitoredLimitPercent: Int?
  private var powerSourceRunLoopSource: CFRunLoopSource?

  func ping(withReply reply: @escaping (String) -> Void) {
    reply("pong")
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
    let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    guard let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let helper = Unmanaged<CapdHelper>.fromOpaque(context).takeUnretainedValue()
      helper.workQueue.async {
        helper.monitorTick()
      }
    }, context)?.takeRetainedValue() else {
      return
    }

    powerSourceRunLoopSource = source
    performOnMain {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
  }

  private func stopPowerSourceMonitoring() {
    guard let source = powerSourceRunLoopSource else { return }
    performOnMain {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    powerSourceRunLoopSource = nil
  }

  private func performOnMain(_ block: () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.sync(execute: block)
    }
  }
}
