import AppKit
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject {

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        print("[LocationManager] Requesting permission, current status: \(statusDescription(manager.authorizationStatus))")
        switch manager.authorizationStatus {
        case .denied, .restricted:
            openSystemSettings()
        default:
            // Menu bar apps are often inactive when the popover is shown.
            // Bring the app to the foreground before asking Core Location.
            NSApp.activate(ignoringOtherApps: true)
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        print("[LocationManager] Authorization changed: \(statusDescription(authorizationStatus))")
        if isAuthorized || authorizationStatus == .denied || authorizationStatus == .restricted {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print("[LocationManager] Location request failed: \(error), status: \(statusDescription(manager.authorizationStatus))")
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            openSystemSettings()
        }
    }
}

private extension LocationManager {
    func statusDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown"
        }
    }
}
