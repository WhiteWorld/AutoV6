import Foundation

// MARK: - XPC Connection Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Verify the connecting process is our main app via code signing
        newConnection.exportedInterface = NSXPCInterface(with: AutoV6HelperProtocol.self)
        newConnection.exportedObject    = IPv6ApplierService()
        newConnection.resume()
        return true
    }
}

// MARK: - Entry Point

let delegate = HelperDelegate()
let listener = NSXPCListener.machService(withName: "com.autov6.AutoV6Helper")
listener.delegate = delegate
listener.resume()

// Run the run loop forever (this is a launchd-managed daemon)
RunLoop.main.run()
