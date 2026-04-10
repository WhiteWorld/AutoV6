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
        // We don't actually consume location data — we only need the
        // permission so that CoreWLAN will return the current SSID. Use
        // the lowest accuracy to minimise power impact.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
        // If permission was already granted at launch, begin updates so
        // that macOS's TCC continues to see an active consumer. Without
        // an active consumer the system can silently revoke the grant.
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func requestPermission() {
        print("[LocationManager] Requesting permission, current status: \(statusDescription(manager.authorizationStatus))")
        // Menu bar apps are often inactive when the popover is shown.
        // Bring the app to the foreground before asking Core Location.
        NSApp.activate(ignoringOtherApps: true)
        switch manager.authorizationStatus {
        case .denied, .restricted:
            openSystemSettings()
        case .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            manager.requestWhenInUseAuthorization()
        }
        // Always (re)start updates. macOS uses the presence of an active
        // location consumer as the signal that the permission is actually
        // in use; without it the toggle in System Settings auto-reverts
        // to OFF a few seconds after the user enables it.
        manager.startUpdatingLocation()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        print("[LocationManager] Authorization changed: \(statusDescription(authorizationStatus))")
        switch authorizationStatus {
        case .authorizedAlways:
            // Keep updates running so TCC continues to observe an active
            // consumer. Stopping here is what was causing System Settings
            // to revert the toggle to OFF shortly after enabling it.
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        default:
            break
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
        @unknown default:
            return "unknown"
        }
    }
}
