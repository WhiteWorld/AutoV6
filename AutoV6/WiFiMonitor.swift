import CoreWLAN
import Observation

@Observable
final class WiFiMonitor: NSObject {

    // MARK: - Published State

    private(set) var currentSSID: String?

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
        wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil
    }

    // MARK: - Internal

    private func handleSSIDChange() {
        let newSSID = wifiClient.interface()?.ssid()
        guard newSSID != currentSSID else { return }
        currentSSID = newSSID

        let ssid = newSSID ?? ""
        print("[WiFiMonitor] SSID changed to: \(ssid.isEmpty ? "(none)" : ssid)")

        guard !ssid.isEmpty, let mode = ruleStore.match(ssid: ssid) else {
            print("[WiFiMonitor] No matching rule, keeping current config.")
            return
        }

        let iface = wifiClient.interface()?.interfaceName ?? "Wi-Fi"
        print("[WiFiMonitor] Matched rule → \(mode.displayName) on \(iface)")
        onModeChange?(mode, iface)
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
