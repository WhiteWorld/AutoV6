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
    private static func activateAppForPrompt() {
        let activate = { NSApp.activate(ignoringOtherApps: true) }
        if Thread.isMainThread { activate() } else { DispatchQueue.main.sync(execute: activate) }
    }

    /// Runs a tool with administrator privileges.
    @discardableResult
    private static func runPrivileged(tool: String, arguments: [String]) -> ApplyResult {
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
}
