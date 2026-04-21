import SwiftUI

@main
struct AutoV6App: App {

    @State private var ruleStore: RuleStore
    @State private var locationManager: LocationManager
    @State private var wifiMonitor: WiFiMonitor

    init() {
        let ruleStore = RuleStore()
        let locationManager = LocationManager()
        let wifiMonitor = WiFiMonitor(ruleStore: ruleStore)

        wifiMonitor.onModeChange = { [weak wifiMonitor] mode, iface in
            Task.detached {
                let result = IPv6Applier.apply(mode, interface: iface)
                await MainActor.run {
                    switch result {
                    case .success:
                        wifiMonitor?.notifyModeApplied(mode)
                        wifiMonitor?.lastError = nil
                    case .cancelled:
                        wifiMonitor?.lastError = nil
                    case .failure(let msg):
                        wifiMonitor?.lastError = msg
                    }
                }
            }
        }

        _ruleStore = State(initialValue: ruleStore)
        _locationManager = State(initialValue: locationManager)
        _wifiMonitor = State(initialValue: wifiMonitor)
    }

    var body: some Scene {
        MenuBarExtra {
            if !locationManager.isAuthorized {
                OnboardingView()
                    .environment(locationManager)
            } else {
                MenuBarView()
                    .environment(ruleStore)
                    .environment(wifiMonitor)
                    .environment(locationManager)
                    .onAppear {
                        wifiMonitor.startMonitoring()
                    }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "wifi")
                if let mode = wifiMonitor.currentIPv6Mode {
                    Text(mode.shortLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
