import Foundation

let delegate = HelperXPCDelegate()
let listener = NSXPCListener(machServiceName: CapdConstants.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.current.run()

