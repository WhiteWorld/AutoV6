import Foundation

final class HelperClient {

    static let helperMachServiceName = "com.autov6.AutoV6Helper"

    private var connection: NSXPCConnection?

    // MARK: - Connect

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: Self.helperMachServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AutoV6HelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            print("[HelperClient] Connection invalidated")
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            print("[HelperClient] Connection interrupted")
            self?.connection = nil
        }
        conn.resume()
        return conn
    }

    private func proxy() -> AutoV6HelperProtocol? {
        if connection == nil {
            connection = makeConnection()
        }
        return connection?.remoteObjectProxyWithErrorHandler { err in
            print("[HelperClient] Remote proxy error: \(err)")
        } as? AutoV6HelperProtocol
    }

    // MARK: - Public API

    func applyMode(_ mode: IPv6Mode, interface: String) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let helper = proxy() else {
                continuation.resume(returning: false)
                return
            }
            helper.applyMode(mode.rawValue, interface: interface) { success in
                continuation.resume(returning: success)
            }
        }
    }

    func helperVersion() async -> String? {
        await withCheckedContinuation { continuation in
            guard let helper = proxy() else {
                continuation.resume(returning: nil)
                return
            }
            helper.helperVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
