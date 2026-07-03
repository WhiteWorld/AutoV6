import AppKit
import Foundation
import Security
import SystemConfiguration

enum IPv6Applier {

    enum ApplyResult {
        case success
        case cancelled
        case failure(String)
    }

    // MARK: - Public

    /// Apply an IPv6 mode to the given BSD interface name (e.g. "en0").
    @discardableResult
    static func apply(_ mode: IPv6Mode, interface ifName: String) -> ApplyResult {
        guard let serviceName = self.serviceName(forInterface: ifName) else {
            return .failure("无法找到接口 \(ifName) 对应的网络服务")
        }

        let args: [String]
        switch mode {
        case .automatic:
            args = ["-setv6automatic", serviceName]
        case .linkLocal:
            args = ["-setv6linklocal", serviceName]
        case .manual:
            guard let cfg = currentIPv6Config(interfaceName: ifName) else {
                return .failure("当前网络没有可用的 IPv6 地址，无法应用手动模式")
            }
            args = ["-setv6manual", serviceName, cfg.address, String(cfg.prefixLength), cfg.router]
        }

        return runPrivileged(tool: "/usr/sbin/networksetup", arguments: args)
    }

    // MARK: - Private helpers

    /// Returns the network service name (e.g. "Wi-Fi") for a BSD interface name (e.g. "en0").
    static func serviceName(forInterface ifName: String) -> String? {
        guard let prefs = SCPreferencesCreate(nil, "AutoV6" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return nil }
        for service in services {
            guard let iface = SCNetworkServiceGetInterface(service),
                  SCNetworkInterfaceGetBSDName(iface) as String? == ifName,
                  let name = SCNetworkServiceGetName(service) as String? else { continue }
            return name
        }
        return nil
    }

    /// Reads the current active IPv6 address, prefix length, and router for an interface
    /// using SCDynamicStore (reflects the live network state, not stored preferences).
    private static func currentIPv6Config(interfaceName ifName: String) -> (address: String, prefixLength: Int, router: String)? {
        guard let store = SCDynamicStoreCreate(nil, "AutoV6" as CFString, nil, nil) else { return nil }

        // Interface-level state: addresses and prefix lengths
        let ifKey = SCDynamicStoreKeyCreateNetworkInterfaceEntity(
            nil, kSCDynamicStoreDomainState, ifName as CFString, kSCEntNetIPv6
        )
        guard let ifDict = SCDynamicStoreCopyValue(store, ifKey) as? NSDictionary,
              let addresses = ifDict[kSCPropNetIPv6Addresses] as? [String],
              let prefixLengths = ifDict[kSCPropNetIPv6PrefixLength] as? [Int],
              let address = addresses.first,
              let prefixLength = prefixLengths.first else { return nil }

        // Service-level state: router
        var router = ""
        if let prefs = SCPreferencesCreate(nil, "AutoV6" as CFString, nil),
           let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] {
            for service in services {
                guard let iface = SCNetworkServiceGetInterface(service),
                      SCNetworkInterfaceGetBSDName(iface) as String? == ifName,
                      let serviceID = SCNetworkServiceGetServiceID(service) as String? else { continue }
                let svcKey = SCDynamicStoreKeyCreateNetworkServiceEntity(
                    nil, kSCDynamicStoreDomainState, serviceID as CFString, kSCEntNetIPv6
                )
                if let svcDict = SCDynamicStoreCopyValue(store, svcKey) as? NSDictionary,
                   let r = svcDict[kSCPropNetIPv6Router] as? String {
                    router = r
                }
                break
            }
        }

        print("[IPv6Applier] Current IPv6: \(address)/\(prefixLength) router=\(router.isEmpty ? "(none)" : router)")
        return (address, prefixLength, router)
    }

    // Cached authorization — acquired once, reused for the lifetime of the app.
    // macOS revokes it after ~5 min of inactivity; we recreate it then.
    private nonisolated(unsafe) static var sharedAuth: AuthorizationRef?
    private static let sudoersPath = "/etc/sudoers.d/autov6-networksetup"

    enum AuthAcquireResult {
        case success(AuthorizationRef)
        case cancelled
        case failed(OSStatus)
    }

    /// Returns a valid AuthorizationRef, prompting the user only when necessary.
    /// Uses SecurityAgent exclusively — it shows Touch ID on systems that have
    /// "Use Touch ID to unlock settings and apps" enabled in System Settings,
    /// and falls back to password entry otherwise. A single dialog, no double-prompt.
    private static func acquireAuth() -> AuthAcquireResult {
        if let auth = sharedAuth {
            var item = AuthorizationItem(name: kAuthorizationRightExecute, valueLength: 0, value: nil, flags: 0)
            var rights = AuthorizationRights(count: 1, items: &item)
            if AuthorizationCopyRights(auth, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess {
                return .success(auth)
            }
            AuthorizationFree(auth, [])
            sharedAuth = nil
        }

        // SecurityAgent is attached to our process; make sure the app is
        // frontmost so the prompt isn't hidden behind other windows.
        activateAppForPrompt()

        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard createStatus == errAuthorizationSuccess, let auth = authRef else {
            return .failed(createStatus)
        }

        var item = AuthorizationItem(name: kAuthorizationRightExecute, valueLength: 0, value: nil, flags: 0)
        var rights = AuthorizationRights(count: 1, items: &item)
        let status = AuthorizationCopyRights(auth, &rights, nil, [.interactionAllowed, .extendRights], nil)
        guard status == errAuthorizationSuccess else {
            print("[IPv6Applier] AuthorizationCopyRights failed: \(status)")
            AuthorizationFree(auth, [])
            return status == errAuthorizationCanceled ? .cancelled : .failed(status)
        }
        sharedAuth = auth
        return .success(auth)
    }

    /// Brings AutoV6 to the foreground so SecurityAgent's prompt is visible.
    /// Only activates when the app isn't already frontmost — otherwise the
    /// activation can unexpectedly pull the MenuBarExtra window open.
    private static func activateAppForPrompt() {
        let hadKeyWindow = NSApp.keyWindow != nil
        guard !hadKeyWindow else { return }
        let activate = { NSApp.activate(ignoringOtherApps: true) }
        if Thread.isMainThread { activate() } else { DispatchQueue.main.sync(execute: activate) }
    }

    /// Runs a tool with administrator privileges.
    @discardableResult
    private static func runPrivileged(tool: String, arguments: [String]) -> ApplyResult {
        if tool == "/usr/sbin/networksetup" {
            let sudoResult = runNetworkSetupWithoutPrompt(arguments: arguments)
            if sudoResult.exitCode == 0 {
                return .success
            }

            if sudoersRuleInstalled(), !isSudoAuthorizationFailure(sudoResult.output) {
                return .failure(sudoResult.output.isEmpty ? "命令执行失败（\(sudoResult.exitCode)）" : sudoResult.output)
            }

            switch installPasswordlessNetworkSetup() {
            case .success:
                let retry = runNetworkSetupWithoutPrompt(arguments: arguments)
                return retry.exitCode == 0
                    ? .success
                    : .failure(retry.output.isEmpty ? "命令执行失败（\(retry.exitCode)）" : retry.output)
            case .cancelled:
                return .cancelled
            case .failure(let msg):
                print("[IPv6Applier] Failed to install sudoers rule: \(msg)")
            }
        }

        let auth: AuthorizationRef
        switch acquireAuth() {
        case .success(let a):
            auth = a
        case .cancelled:
            return .cancelled
        case .failed(let status):
            return .failure("授权失败（\(status)）")
        }

        // AuthorizationExecuteWithPrivileges is deprecated and unavailable in Swift,
        // but the symbol still exists in Security.framework — load it via dlsym.
        typealias ExecFn = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "AuthorizationExecuteWithPrivileges") else {
            return .failure("系统符号加载失败")
        }
        let execFn = unsafeBitCast(sym, to: ExecFn.self)

        var cArgs = arguments.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        let execStatus = tool.withCString { cTool in
            execFn(auth, cTool, AuthorizationFlags(), &cArgs, nil)
        }
        return execStatus == errAuthorizationSuccess
            ? .success
            : .failure("命令执行失败（\(execStatus)）")
    }

    private static func runNetworkSetupWithoutPrompt(arguments: [String]) -> (exitCode: Int32, output: String) {
        runProcess("/usr/bin/sudo", arguments: ["-n", "/usr/sbin/networksetup"] + arguments)
    }

    private static func sudoersRuleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    private static func isSudoAuthorizationFailure(_ output: String) -> Bool {
        let message = output.lowercased()
        return message.contains("password is required")
            || message.contains("a terminal is required")
            || message.contains("no tty present")
            || message.contains("not allowed to execute")
    }

    /// Installs a narrow sudoers rule so AutoV6 can run only the IPv6-related
    /// networksetup commands without repeatedly invoking SecurityAgent.
    private static func installPasswordlessNetworkSetup() -> ApplyResult {
        let auth: AuthorizationRef
        switch acquireAuth() {
        case .success(let a):
            auth = a
        case .cancelled:
            return .cancelled
        case .failed(let status):
            return .failure("授权失败（\(status)）")
        }

        let rule = "\(sudoersUserSpec()) ALL=(root) NOPASSWD: /usr/sbin/networksetup -setv6automatic *, /usr/sbin/networksetup -setv6linklocal *, /usr/sbin/networksetup -setv6manual *"
        let script = """
        set -eu
        path=\(shellQuote(sudoersPath))
        tmp=$(/usr/bin/mktemp /tmp/autov6-sudoers.XXXXXX)
        cleanup() { /bin/rm -f "$tmp"; }
        trap cleanup EXIT
        /usr/bin/printf '%s\\n' \(shellQuote("# AutoV6: allow this user to change IPv6 mode without repeated password prompts.")) \(shellQuote(rule)) > "$tmp"
        /bin/chown root:wheel "$tmp"
        /bin/chmod 0440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        /bin/mv "$tmp" "$path"
        trap - EXIT
        """

        let result = runPrivilegedShell(script, auth: auth)
        if result == errAuthorizationSuccess {
            return .success
        }
        return .failure("免密授权安装失败（\(result)）")
    }

    private static func runPrivilegedShell(_ script: String, auth: AuthorizationRef) -> OSStatus {
        typealias ExecFn = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "AuthorizationExecuteWithPrivileges") else {
            return errAuthorizationInternal
        }
        let execFn = unsafeBitCast(sym, to: ExecFn.self)

        let shellArguments = ["-c", script]
        var cArgs: [UnsafeMutablePointer<CChar>?] = shellArguments.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        var pipe: UnsafeMutablePointer<FILE>?
        let status = "/bin/sh".withCString { cTool in
            execFn(auth, cTool, AuthorizationFlags(), &cArgs, &pipe)
        }
        if let pipe {
            var buffer = [CChar](repeating: 0, count: 4096)
            while fread(&buffer, 1, buffer.count, pipe) > 0 {}
            fclose(pipe)
        }
        return status
    }

    private static func runProcess(_ executable: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (127, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    private static func sudoersUserSpec() -> String {
        let name = NSUserName()
        return name.map { character in
            switch character {
            case "\\", " ", "\t", ":", ",", "=":
                return "\\\(character)"
            default:
                return String(character)
            }
        }.joined()
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
