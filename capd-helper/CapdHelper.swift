import Foundation
import os.log

final class CapdHelper: NSObject, CapdHelperProtocol {
  private let logger = Logger(subsystem: CapdConstants.helperLabel, category: "helper")
  private let limiter = ChargeLimiter()
  private let workQueue = DispatchQueue(label: "com.example.capd.helper.work")
  private var monitorTimer: DispatchSourceTimer?
  private var monitoredLimitPercent: Int?

  func ping(withReply reply: @escaping (String) -> Void) {
    reply("pong")
  }

  func setChargeLimit(_ percent: Int, withReply reply: @escaping (NSError?) -> Void) {
    let clamped = CapdConstants.clampLimit(percent)
    logger.info("setChargeLimit requested: \(clamped, privacy: .public)")
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.limiter.setLimit(clamped)
        self.startMonitoring(limitPercent: clamped)
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

    if monitorTimer == nil {
      let timer = DispatchSource.makeTimerSource(queue: workQueue)
      timer.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30), leeway: .seconds(5))
      timer.setEventHandler { [weak self] in
        self?.monitorTick()
      }
      timer.resume()
      monitorTimer = timer
    }

    monitorTick()
  }

  private func stopMonitoring() {
    monitoredLimitPercent = nil
    monitorTimer?.cancel()
    monitorTimer = nil
  }

  private func monitorTick() {
    guard let limit = monitoredLimitPercent else { return }
    do {
      try limiter.setLimit(limit)
    } catch {
      logger.error("monitor tick failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
