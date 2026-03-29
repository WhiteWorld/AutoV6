import Foundation

@objc(AutoV6HelperProtocol)
protocol AutoV6HelperProtocol {
    /// Apply an IPv6 mode to the given interface.
    /// - Parameters:
    ///   - mode: One of "automatic", "linklocal", "off"
    ///   - interface: Network interface name, e.g. "Wi-Fi"
    ///   - reply: Called with true on success, false on failure
    func applyMode(_ mode: String, interface: String, reply: @escaping (Bool) -> Void)

    /// Return the bundle version of the running helper.
    func helperVersion(reply: @escaping (String) -> Void)
}
