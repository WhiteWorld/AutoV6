import SwiftUI

@main
struct AutoV6App: App {

    // MARK: - Shared State

    @State private var ruleStore        = RuleStore()
    @State private var locationManager  = LocationManager()
    @State private var helperInstaller  = HelperInstaller()
    @State private var helperClient     = HelperClient()

    // WiFiMonitor depends on ruleStore, created lazily
    @State private var wifiMonitor: WiFiMonitor?

    // MARK: - Body

    var body: some Scene {
        MenuBarExtra {
            if needsOnboarding {
                OnboardingView()
                    .environment(locationManager)
                    .environment(helperInstaller)
            } else {
                MenuBarView()
                    .environment(ruleStore)
                    .environment(wifiMonitor ?? makeMonitor())
                    .environment(helperInstaller)
                    .environment(locationManager)
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Menu Bar Label

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi")
        }
    }

    // MARK: - Onboarding Check

    private var needsOnboarding: Bool {
        if !locationManager.isAuthorized { return true }
        if case .notInstalled = helperInstaller.state { return true }
        if case .unknown = helperInstaller.state { return true }
        return false
    }

    // MARK: - WiFiMonitor

    private func makeMonitor() -> WiFiMonitor {
        let monitor = WiFiMonitor(ruleStore: ruleStore)
        monitor.onModeChange = { mode, iface in
            Task {
                let success = await helperClient.applyMode(mode, interface: iface)
                print("[App] applyMode \(mode.rawValue) on \(iface): \(success)")
            }
        }
        monitor.startMonitoring()
        wifiMonitor = monitor
        return monitor
    }
}
