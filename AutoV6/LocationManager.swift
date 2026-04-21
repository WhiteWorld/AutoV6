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
        // Only run updates once we're actually authorised. Starting
        // updates while the status is .notDetermined/.denied has been
        // observed to crash inside CoreLocation on macOS 26 when the
        // grant flips to authorizedAlways while an error is in flight
        // (EXC_BAD_ACCESS in objc_retain on the CoreLocation read queue).
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func requestPermission() {
        print("[LocationManager] Requesting permission, current status: \(statusDescription(manager.authorizationStatus))")
        switch manager.authorizationStatus {
        case .denied, .restricted:
            openSystemSettings()
        case .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            guard permissionPanel == nil else { return }
            showPermissionWindow()
            manager.requestAlwaysAuthorization()
        }
    }

    private func showPermissionWindow() {
        guard permissionPanel == nil else { return }
        let win = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.level = .floating
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionPanel = win
    }

    private var permissionPanel: NSWindow?

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }
}

// NSWindow subclass that allows borderless windows to become key,
// which is required for macOS TCC to attach the permission dialog.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        print("[LocationManager] Authorization changed: \(statusDescription(authorizationStatus))")
        permissionPanel?.close()
        permissionPanel = nil
        switch authorizationStatus {
        case .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Failures are expected while the user hasn't granted permission
        // yet — we intentionally keep the manager running so TCC sees a
        // live consumer. Do not auto-open System Settings here.
        print("[LocationManager] Location request failed: \(error), status: \(statusDescription(manager.authorizationStatus))")
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
