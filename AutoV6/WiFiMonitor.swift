import CoreWLAN
import Observation
import SystemConfiguration

@Observable
final class WiFiMonitor: NSObject {

    // MARK: - Published State

    private(set) var currentSSID: String?
    private(set) var currentIPv6Mode: IPv6Mode?
    var lastError: String?

    // MARK: - Dependencies

    private let ruleStore: RuleStore
    var onModeChange: ((IPv6Mode, String) -> Void)?   // (mode, interface)

    // MARK: - Private

    private let wifiClient = CWWiFiClient.shared()

    // MARK: - Init

    init(ruleStore: RuleStore) {
        self.ruleStore = ruleStore
        super.init()
        currentSSID = wifiClient.interface()?.ssid()
        if let ifName = wifiClient.interface()?.interfaceName {
            currentIPv6Mode = Self.readSystemIPv6Mode(interfaceName: ifName)
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        wifiClient.delegate = self
        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
            try wifiClient.startMonitoringEvent(with: .bssidDidChange)
        } catch {
            print("[WiFiMonitor] Failed to start monitoring: \(error)")
        }
    }

    func stopMonitoring() {
        try? wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil
    }

    // MARK: - Internal

    private func handleSSIDChange() {
        let newSSID = wifiClient.interface()?.ssid()
        guard newSSID != currentSSID else { return }
        currentSSID = newSSID

        let ssid = newSSID ?? ""
        print("[WiFiMonitor] SSID changed to: \(ssid.isEmpty ? "(none)" : ssid)")

        let ifName = wifiClient.interface()?.interfaceName ?? "en0"

        guard !ssid.isEmpty, let mode = ruleStore.match(ssid: ssid) else {
            print("[WiFiMonitor] No matching rule, keeping current config.")
            currentIPv6Mode = Self.readSystemIPv6Mode(interfaceName: ifName)
            return
        }

        print("[WiFiMonitor] Matched rule → \(mode.displayName) on \(ifName)")
        onModeChange?(mode, ifName)
    }

    /// Applies the matching rule for the current SSID immediately, if one exists.
    func applyCurrentRule() {
        guard let ssid = currentSSID, !ssid.isEmpty,
              let mode = ruleStore.match(ssid: ssid),
              let ifName = wifiClient.interface()?.interfaceName else { return }
        print("[WiFiMonitor] Applying rule immediately → \(mode.displayName) on \(ifName)")
        onModeChange?(mode, ifName)
    }

    /// Re-reads the current SSID and system IPv6 mode. Call this whenever the UI becomes visible.
    func refresh() {
        currentSSID = wifiClient.interface()?.ssid()
        if let ifName = wifiClient.interface()?.interfaceName {
            currentIPv6Mode = Self.readSystemIPv6Mode(interfaceName: ifName)
        }
    }

    /// Called after a mode has been applied so the displayed state stays in sync.
    func notifyModeApplied(_ mode: IPv6Mode) {
        currentIPv6Mode = mode
    }

    // MARK: - System IPv6 Query

    /// Reads the stored IPv6 ConfigMethod from SystemConfiguration for the given BSD interface name.
    static func readSystemIPv6Mode(interfaceName: String) -> IPv6Mode? {
        guard let prefs = SCPreferencesCreate(nil, "AutoV6" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return nil }
        for service in services {
            guard let iface = SCNetworkServiceGetInterface(service),
                  SCNetworkInterfaceGetBSDName(iface) as String? == interfaceName,
                  let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv6),
                  let config = SCNetworkProtocolGetConfiguration(proto) as NSDictionary?,
                  let method = config[kSCPropNetIPv6ConfigMethod] as? String
            else { continue }
            switch method {
            case "Automatic":  return .automatic
            case "LinkLocal":  return .linkLocal
            default:           return .manual
            }
        }
        return nil
    }

    /// Returns the network service name (e.g. "Wi-Fi") for a given BSD interface name (e.g. "en0").
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
}

// MARK: - CWEventDelegate

extension WiFiMonitor: CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        handleSSIDChange()
    }

    func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        handleSSIDChange()
    }
}
