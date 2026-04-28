import AppKit
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject {

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var isUpdating = false
    private var lastPermissionRequestTime: Date = .distantPast

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
            isUpdating = true
        }
        // If the system permission dialog is dismissed without a choice
        // (unusual but possible), the delegate callback never fires and
        // the KeyableWindow leaks. When the app next becomes active, if
        // the status hasn't changed the dialog was skipped — clean up.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive(_ note: Notification) {
        guard permissionPanel != nil,
              manager.authorizationStatus == .notDetermined else { return }
        permissionPanel?.close()
        permissionPanel = nil
    }

    func requestPermission() {
        print("[LocationManager] Requesting permission, current status: \(statusDescription(manager.authorizationStatus))")
        switch manager.authorizationStatus {
        case .denied, .restricted:
            openSystemSettings()
        case .authorizedAlways:
            if !isUpdating {
                manager.startUpdatingLocation()
                isUpdating = true
            }
        default:
            // Debounce rapid clicks — calling requestAlwaysAuthorization() while
            // a previous dialog is still in flight can confuse CoreLocation and
            // cause multiple system dialogs to stack, or KeyableWindows to pile up.
            let now = Date()
            guard now.timeIntervalSince(lastPermissionRequestTime) > 2.0 else {
                print("[LocationManager] Ignoring rapid re-request at \(now)")
                return
            }
            lastPermissionRequestTime = now

            // Clean up any stale panel leaked from a previous cancelled attempt.
            permissionPanel?.close()
            permissionPanel = nil
            showPermissionWindow()
            manager.requestAlwaysAuthorization()
        }
    }

    private func showPermissionWindow() {
        guard permissionPanel == nil else { return }
        let hadKeyWindow = NSApp.keyWindow != nil
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
        // Only activate if the app wasn't already frontmost (e.g. the
        // MenuBarExtra popup wasn't open). Aggressively activating a
        // background agent app can unexpectedly pull the MenuBarExtra
        // window open on some macOS versions.
        if !hadKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
        }
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
            if !isUpdating {
                manager.startUpdatingLocation()
                isUpdating = true
            }
        case .denied, .restricted:
            isUpdating = false
            // CoreLocation already stops internally when the grant is
            // revoked. Calling stopUpdatingLocation() from this delegate
            // while an error is in flight triggers an EXC_BAD_ACCESS on
            // macOS 26 (over-release inside the location read queue).
            break
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
