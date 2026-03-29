import Foundation

final class IPv6ApplierService: NSObject, AutoV6HelperProtocol {

    // MARK: - AutoV6HelperProtocol

    func applyMode(_ mode: String, interface: String, reply: @escaping (Bool) -> Void) {
        guard let arg = networksetupArg(for: mode) else {
            print("[Helper] Unknown mode: \(mode)")
            reply(false)
            return
        }

        var arguments: [String]
        // -setv6off and -setv6linklocal take only the interface
        // -setv6automatic also takes only the interface
        arguments = [arg, interface]

        run(launchPath: "/usr/sbin/networksetup", arguments: arguments, reply: reply)
    }

    func helperVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        reply(version ?? "unknown")
    }

    // MARK: - Helpers

    private func networksetupArg(for mode: String) -> String? {
        switch mode {
        case "automatic": return "-setv6automatic"
        case "linklocal":  return "-setv6linklocal"
        case "off":        return "-setv6off"
        default:           return nil
        }
    }

    private func run(launchPath: String, arguments: [String], reply: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let success = process.terminationStatus == 0
            print("[Helper] \(launchPath) \(arguments.joined(separator: " ")) → status=\(process.terminationStatus) output=\(output)")
            reply(success)
        } catch {
            print("[Helper] Process error: \(error)")
            reply(false)
        }
    }
}
