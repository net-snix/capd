import Foundation
import IOKit

private enum SMCCommand: UInt8 {
  case readBytes = 5
  case readKeyInfo = 9
}

struct SMCKeyInfo {
  let dataSize: Int
  let dataType: UInt32
  let dataAttributes: UInt8

  var dataTypeString: String {
    fourCharCodeString(dataType)
  }
}

enum SMCError: LocalizedError {
  case serviceNotFound
  case openFailed(kern_return_t)
  case callFailed(kern_return_t, command: String)
  case keyNotFound(String)
  case invalidKey(String)
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
    case .commandFailed(let result, let status):
      return "SMC command failed (result \(result), status \(status))."
    }
  }
}

final class SMCConnection {
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

private func hexBytes(_ bytes: [UInt8]) -> String {
  bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

let defaultKeys = [
  "BCLM",
  "CHTE",
  "CH0C",
  "CH0B",
  "CHIE",
  "CH0J",
  "CH0I",
  "AC-W",
  "BUIC",
]

let args = Array(CommandLine.arguments.dropFirst())
let keys = args.isEmpty ? defaultKeys : args

let smc = SMCConnection()
do {
  try smc.open()
} catch {
  print("SMC open failed: \(error.localizedDescription)")
  exit(1)
}
defer { smc.close() }

print("SMC key probe:")
for key in keys {
  do {
    let info = try smc.readKeyInfo(key)
    let attrs = String(format: "0x%02X", info.dataAttributes)
    var bytesText = "read_failed"
    if let bytes = try? smc.readKey(key, dataSize: info.dataSize) {
      bytesText = hexBytes(bytes)
    }
    print("\(key): size=\(info.dataSize) type=\(info.dataTypeString) attrs=\(attrs) bytes=\(bytesText)")
  } catch {
    print("\(key): missing")
  }
}
