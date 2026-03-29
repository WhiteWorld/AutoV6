import Foundation
import ServiceManagement

/// Manages SMJobBless installation and version checking of the privileged helper.
@Observable
final class HelperInstaller {

    enum InstallState {
        case unknown
        case notInstalled
        case installed(version: String)
        case error(String)
    }

    private(set) var state: InstallState = .unknown

    private let helperClient = HelperClient()
    private let helperBundleID = "com.autov6.AutoV6Helper"

    // MARK: - Check

    func checkInstallation() async {
        let version = await helperClient.helperVersion()
        if let version {
            state = .installed(version: version)
        } else {
            state = .notInstalled
        }
    }

    // MARK: - Install

    @MainActor
    func install() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var cfError: Unmanaged<CFError>?
            let success = SMJobBless(
                kSMDomainSystemLaunchd,
                helperBundleID as CFString,
                nil,
                &cfError
            )
            if success {
                continuation.resume()
            } else {
                let err = cfError?.takeRetainedValue() as Error? ?? NSError(
                    domain: "HelperInstaller",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "SMJobBless failed"]
                )
                continuation.resume(throwing: err)
            }
        }
        await checkInstallation()
    }

    // MARK: - Version Upgrade

    /// Returns true if the embedded helper is newer than the running helper.
    func needsUpgrade() -> Bool {
        guard let embeddedURL = Bundle.main.url(
            forAuxiliaryExecutable: "Contents/Library/LaunchServices/\(helperBundleID)"
        ),
        let embeddedBundle = Bundle(url: embeddedURL),
        let embeddedVersion = embeddedBundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        else { return false }

        if case .installed(let running) = state {
            return embeddedVersion.compare(running, options: .numeric) == .orderedDescending
        }
        return false
    }
}
