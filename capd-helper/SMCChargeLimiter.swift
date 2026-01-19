import Foundation
import IOKit
import IOKit.ps

enum ChargeLimiterError: LocalizedError {
  case invalidArgument(String)
  case notSupported(String)
  case smcFailure(String)

  var errorDescription: String? {
    switch self {
    case .invalidArgument(let message),
         .notSupported(let message),
         .smcFailure(let message):
      return message
    }
  }

  var code: CapdHelperErrorCode {
    switch self {
    case .invalidArgument:
      return .invalidArgument
    case .notSupported:
      return .notSupported
    case .smcFailure:
      return .smcFailure
    }
  }
}

final class ChargeLimiter {
  private let chargeLimitKey = "BCLM"
  private let magSafeKey = "ACLC"
  private struct ChargingControl {
    let key: String
    let dataSize: Int
    let dataType: UInt32
    let dataAttributes: UInt8
    let onBytes: [UInt8]
    let offBytes: [UInt8]
  }

  private static let chargingControls: [ChargingControl] = {
    guard let ui32 = fourCharCode("ui32"),
          let hex = fourCharCode("hex_") else {
      return []
    }
    return [
      ChargingControl(
        key: "CHTE",
        dataSize: 4,
        dataType: ui32,
        dataAttributes: 0xD4,
        onBytes: [0x00, 0x00, 0x00, 0x00],
        offBytes: [0x01, 0x00, 0x00, 0x00]
      ),
      ChargingControl(
        key: "CH0C",
        dataSize: 1,
        dataType: hex,
        dataAttributes: 0xD4,
        onBytes: [0x00],
        offBytes: [0x01]
      ),
    ]
  }()
  private let hysteresisPercent = 3
  private var lastChargingEnabled: Bool?
  private var magSafeSupported: Bool?
  private var lastMagSafeColor: UInt8?

  func setLimit(_ percent: Int) throws {
    let clamped = CapdConstants.clampLimit(percent)
    guard clamped >= CapdConstants.minChargeLimitPercent,
          clamped <= CapdConstants.maxChargeLimitPercent else {
      throw ChargeLimiterError.invalidArgument(
        "Limit must be \(CapdConstants.minChargeLimitPercent)-\(CapdConstants.maxChargeLimitPercent)."
      )
    }

    do {
      try setBCLMLimit(clamped)
      if let battery = try? readBatteryState() {
        updateMagSafeState(limit: clamped, battery: battery, chargingEnabled: nil)
      }
      return
    } catch let error as ChargeLimiterError {
      if case .notSupported = error {
        try applyChargingLimit(clamped)
        return
      }
      throw error
    }
  }

  func clearLimit() throws {
    do {
      try setBCLMLimit(CapdConstants.maxChargeLimitPercent)
      resetMagSafeState()
      return
    } catch let error as ChargeLimiterError {
      if case .notSupported = error {
        try setChargingEnabled(true)
        lastChargingEnabled = true
        resetMagSafeState()
        return
      }
      throw error
    }
  }

  private func setBCLMLimit(_ percent: Int) throws {
    try withSMC { smc in
      let info: SMCKeyInfo
      do {
        info = try smc.readKeyInfo(chargeLimitKey)
      } catch let error as SMCError {
        throw mapSMCError(error, key: chargeLimitKey)
      }

      let bytes = try encodeLimit(percent, info: info)

      do {
        try smc.writeKey(chargeLimitKey, bytes: bytes, dataSize: info.dataSize)
      } catch let error as SMCError {
        throw mapSMCError(error, key: chargeLimitKey)
      }
    }
  }

  private func applyChargingLimit(_ limit: Int) throws {
    let battery = try readBatteryState()
    guard battery.isPluggedIn else {
      lastChargingEnabled = nil
      updateMagSafeState(limit: limit, battery: battery, chargingEnabled: nil)
      return
    }

    let lowerBound = max(CapdConstants.minChargeLimitPercent, limit - hysteresisPercent)
    let shouldEnable: Bool

    if battery.percent <= lowerBound {
      shouldEnable = true
    } else if battery.percent >= limit {
      shouldEnable = false
    } else if let lastChargingEnabled {
      shouldEnable = lastChargingEnabled
    } else {
      shouldEnable = true
    }

    if lastChargingEnabled != shouldEnable {
      try setChargingEnabled(shouldEnable)
      lastChargingEnabled = shouldEnable
    }

    updateMagSafeState(limit: limit, battery: battery, chargingEnabled: shouldEnable)
  }

  private func updateMagSafeState(limit: Int, battery: BatteryState, chargingEnabled: Bool?) {
    guard limit < CapdConstants.maxChargeLimitPercent else {
      setMagSafeColorIfNeeded(0x00)
      return
    }

    guard battery.isPluggedIn else {
      setMagSafeColorIfNeeded(0x00)
      return
    }

    let shouldGreen: Bool
    if let chargingEnabled {
      shouldGreen = !chargingEnabled
    } else {
      shouldGreen = !battery.isCharging && battery.percent >= limit
    }

    setMagSafeColorIfNeeded(shouldGreen ? 0x03 : 0x00)
  }

  private func resetMagSafeState() {
    setMagSafeColorIfNeeded(0x00)
  }

  private func setMagSafeColorIfNeeded(_ color: UInt8) {
    guard lastMagSafeColor != color else { return }
    guard magSafeSupported != false else { return }

    do {
      try withSMC { smc in
        if magSafeSupported == nil {
          guard let ui8 = fourCharCode("ui8 ") else {
            magSafeSupported = false
            return
          }

          do {
            let info = try smc.readKeyInfo(magSafeKey)
            let matches = info.dataSize == 1 &&
              info.dataType == ui8 &&
              info.dataAttributes == 0xD4
            guard matches else {
              magSafeSupported = false
              return
            }
          } catch {
            magSafeSupported = false
            return
          }

          magSafeSupported = true
        }

        try smc.writeKey(magSafeKey, bytes: [color], dataSize: 1)
        lastMagSafeColor = color
      }
    } catch {
      return
    }
  }

  private func setChargingEnabled(_ enabled: Bool) throws {
    try withSMC { smc in
      var probeNotes: [String] = []

      for control in Self.chargingControls {
        let info: SMCKeyInfo
        do {
          info = try smc.readKeyInfo(control.key)
        } catch {
          if let _ = try? smc.readKey(control.key, dataSize: control.dataSize) {
            let desired = enabled ? control.onBytes : control.offBytes
            do {
              try smc.writeKey(control.key, bytes: desired, dataSize: control.dataSize)
            } catch let error as SMCError {
              throw mapSMCError(error, key: control.key)
            }
            return
          }

          probeNotes.append("\(control.key)=\(error.localizedDescription)")
          continue
        }

        let sizeMatches = info.dataSize == control.dataSize
        let typeMatches = info.dataType == control.dataType
        let attrsMatches = info.dataAttributes == control.dataAttributes

        if !sizeMatches {
          probeNotes.append("\(control.key)=size(\(info.dataSize))")
          continue
        }

        if !typeMatches || !attrsMatches {
          probeNotes.append("\(control.key)=type/attr mismatch")
        }

        let desired = enabled ? control.onBytes : control.offBytes
        if let current = try? smc.readKey(control.key, dataSize: control.dataSize),
           current == desired {
          return
        }

        do {
          try smc.writeKey(control.key, bytes: desired, dataSize: control.dataSize)
        } catch let error as SMCError {
          throw mapSMCError(error, key: control.key)
        }
        return
      }

      let suffix = probeNotes.isEmpty ? "" : " (\(probeNotes.joined(separator: ", ")))"
      throw ChargeLimiterError.notSupported("Charging control keys are not supported on this Mac.\(suffix)")
    }
  }

  private func encodeLimit(_ percent: Int, info: SMCKeyInfo) throws -> [UInt8] {
    switch info.dataSize {
    case 1:
      return [UInt8(percent)]
    case 2:
      let value = UInt16(percent)
      return [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    default:
      throw ChargeLimiterError.notSupported(
        "\(chargeLimitKey) data size \(info.dataSize) is not supported (type \(info.dataTypeString))."
      )
    }
  }


  private func readBatteryState() throws -> BatteryState {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
          let first = sources.first,
          let description = IOPSGetPowerSourceDescription(info, first)?
            .takeUnretainedValue() as? [String: Any] else {
      throw ChargeLimiterError.smcFailure("Battery status unavailable.")
    }

    let state = description[kIOPSPowerSourceStateKey as String] as? String
    let isPluggedIn = state == kIOPSACPowerValue
    let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false

    let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
    let max = description[kIOPSMaxCapacityKey as String] as? Int ?? 0
    let percent: Int

    if max > 0 {
      percent = Int((Double(current) / Double(max) * 100.0).rounded())
    } else {
      percent = current
    }

    return BatteryState(percent: percent, isPluggedIn: isPluggedIn, isCharging: isCharging)
  }

  private func withSMC<T>(_ body: (SMCConnection) throws -> T) throws -> T {
    let smc = SMCConnection()
    try smc.open()
    defer { smc.close() }
    return try body(smc)
  }

  private func mapSMCError(_ error: SMCError, key: String) -> ChargeLimiterError {
    switch error {
    case .keyNotFound:
      return .notSupported("\(key) is not supported on this Mac.")
    case .unsupportedDataSize(let size, let typeString):
      return .notSupported("\(key) data format \(typeString) (\(size) bytes) is not supported.")
    case .invalidKey:
      return .smcFailure("Invalid SMC key \(key).")
    default:
      return .smcFailure(error.localizedDescription)
    }
  }
}

private struct BatteryState {
  let percent: Int
  let isPluggedIn: Bool
  let isCharging: Bool
}

private enum SMCCommand: UInt8 {
  case readBytes = 5
  case readKeyInfo = 9
  case writeBytes = 6
}

private struct SMCKeyInfo {
  let dataSize: Int
  let dataType: UInt32
  let dataAttributes: UInt8

  var dataTypeString: String {
    fourCharCodeString(dataType)
  }
}

private enum SMCError: LocalizedError {
  case serviceNotFound
  case openFailed(kern_return_t)
  case callFailed(kern_return_t, command: String)
  case keyNotFound(String)
  case invalidKey(String)
  case unsupportedDataSize(Int, String)
  case commandFailed(result: UInt8, status: UInt8)

  var errorDescription: String? {
    switch self {
    case .serviceNotFound:
      return "AppleSMC service not found."
    case .openFailed(let kr):
      return "Failed to open AppleSMC: \(kernReturnMessage(kr))."
    case .callFailed(let kr, let command):
      return "SMC command '\(command)' failed: \(kernReturnMessage(kr))."
    case .keyNotFound(let key):
      return "SMC key \(key) not found."
    case .invalidKey(let key):
      return "SMC key \(key) must be 4 ASCII characters."
    case .unsupportedDataSize(let size, let typeString):
      return "SMC key has unsupported size \(size) (type \(typeString))."
    case .commandFailed(let result, let status):
      return "SMC command failed (result \(result), status \(status))."
    }
  }
}

private final class SMCConnection {
  private var connection: io_connect_t = 0
  private var userClientOpened = false

  func open() throws {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service != 0 else {
      throw SMCError.serviceNotFound
    }
    var result = IOServiceOpen(service, mach_task_self_, 1, &connection)
    if result != kIOReturnSuccess {
      result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    }
    IOObjectRelease(service)
    guard result == kIOReturnSuccess else {
      throw SMCError.openFailed(result)
    }

    let openResult = IOConnectCallMethod(
      connection,
      UInt32(0),
      nil,
      0,
      nil,
      0,
      nil,
      nil,
      nil,
      nil
    )
    if openResult == kIOReturnSuccess {
      userClientOpened = true
    }
  }

  func close() {
    if connection != 0 {
      if userClientOpened {
        IOConnectCallMethod(
          connection,
          UInt32(1),
          nil,
          0,
          nil,
          0,
          nil,
          nil,
          nil,
          nil
        )
        userClientOpened = false
      }
      IOServiceClose(connection)
      connection = 0
    }
  }

  func readKeyInfo(_ key: String) throws -> SMCKeyInfo {
    guard let keyCode = fourCharCode(key) else {
      throw SMCError.invalidKey(key)
    }

    var input = SMCKeyData_t()
    input.key = keyCode
    input.data8 = SMCCommand.readKeyInfo.rawValue

    var output = SMCKeyData_t()
    let result = callSMC(&input, &output)
    guard result == kIOReturnSuccess else {
      throw SMCError.callFailed(result, command: "readKeyInfo")
    }
    guard output.result == 0, output.keyInfo.dataSize > 0 else {
      throw SMCError.keyNotFound(key)
    }

    return SMCKeyInfo(
      dataSize: Int(output.keyInfo.dataSize),
      dataType: output.keyInfo.dataType,
      dataAttributes: output.keyInfo.dataAttributes
    )
  }

  func writeKey(_ key: String, bytes: [UInt8], dataSize: Int) throws {
    guard let keyCode = fourCharCode(key) else {
      throw SMCError.invalidKey(key)
    }

    var input = SMCKeyData_t()
    input.key = keyCode
    input.data8 = SMCCommand.writeBytes.rawValue
    input.keyInfo.dataSize = UInt32(dataSize)
    input.setBytes(bytes)

    var output = SMCKeyData_t()
    let result = callSMC(&input, &output)
    guard result == kIOReturnSuccess else {
      throw SMCError.callFailed(result, command: "writeBytes")
    }
    guard output.result == 0 else {
      throw SMCError.commandFailed(result: output.result, status: output.status)
    }
  }

  func readKey(_ key: String, dataSize: Int) throws -> [UInt8] {
    guard let keyCode = fourCharCode(key) else {
      throw SMCError.invalidKey(key)
    }

    var input = SMCKeyData_t()
    input.key = keyCode
    input.data8 = SMCCommand.readBytes.rawValue
    input.keyInfo.dataSize = UInt32(dataSize)

    var output = SMCKeyData_t()
    let result = callSMC(&input, &output)
    guard result == kIOReturnSuccess else {
      throw SMCError.callFailed(result, command: "readBytes")
    }
    guard output.result == 0 else {
      throw SMCError.commandFailed(result: output.result, status: output.status)
    }
    return output.getBytes(count: dataSize)
  }

  private func callSMC(_ input: inout SMCKeyData_t, _ output: inout SMCKeyData_t) -> kern_return_t {
    let inputSize = MemoryLayout<SMCKeyData_t>.stride
    var outputSize = MemoryLayout<SMCKeyData_t>.stride
    return IOConnectCallStructMethod(
      connection,
      UInt32(2),
      &input,
      inputSize,
      &output,
      &outputSize
    )
  }
}

private struct SMCKeyData_vers_t {
  var major: UInt8 = 0
  var minor: UInt8 = 0
  var build: UInt8 = 0
  var reserved: UInt8 = 0
  var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
  var version: UInt16 = 0
  var length: UInt16 = 0
  var cpuPLimit: UInt32 = 0
  var gpuPLimit: UInt32 = 0
  var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
  var dataSize: UInt32 = 0
  var dataType: UInt32 = 0
  var dataAttributes: UInt8 = 0
  var reserved: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private typealias SMCBytes = (
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData_t {
  var key: UInt32 = 0
  var vers: SMCKeyData_vers_t = SMCKeyData_vers_t()
  var pLimitData: SMCKeyData_pLimitData_t = SMCKeyData_pLimitData_t()
  var keyInfo: SMCKeyData_keyInfo_t = SMCKeyData_keyInfo_t()
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: SMCBytes = zeroSMCBytes()

  mutating func setBytes(_ data: [UInt8]) {
    withUnsafeMutableBytes(of: &bytes) { rawBuffer in
      let buffer = rawBuffer.bindMemory(to: UInt8.self)
      for index in buffer.indices {
        buffer[index] = 0
      }
      for (index, value) in data.enumerated() where index < buffer.count {
        buffer[index] = value
      }
    }
  }

  func getBytes(count: Int) -> [UInt8] {
    withUnsafeBytes(of: bytes) { rawBuffer in
      Array(rawBuffer.prefix(count))
    }
  }
}

private func zeroSMCBytes() -> SMCBytes {
  (0, 0, 0, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0,
   0, 0, 0, 0, 0, 0, 0, 0)
}

private func fourCharCode(_ string: String) -> UInt32? {
  let bytes = Array(string.utf8)
  guard bytes.count == 4 else { return nil }
  return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

private func fourCharCodeString(_ code: UInt32) -> String {
  let bytes: [UInt8] = [
    UInt8((code >> 24) & 0xFF),
    UInt8((code >> 16) & 0xFF),
    UInt8((code >> 8) & 0xFF),
    UInt8(code & 0xFF),
  ]
  return String(bytes: bytes, encoding: .ascii) ?? "????"
}

private func kernReturnMessage(_ kr: kern_return_t) -> String {
  if let cString = mach_error_string(kr) {
    return String(cString: cString)
  }
  return "kern_return_t=\(kr)"
}
