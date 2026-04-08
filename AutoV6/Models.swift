import Foundation

// MARK: - IPv6Mode

enum IPv6Mode: String, Codable, CaseIterable, Identifiable {
    case automatic  = "automatic"
    case manual     = "manual"
    case linkLocal  = "linklocal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "自动"
        case .manual:    return "手动"
        case .linkLocal: return "仅本地链接"
        }
    }

    /// Short label shown in the menu bar
    var shortLabel: String {
        switch self {
        case .automatic: return "自动"
        case .manual:    return "手动"
        case .linkLocal: return "本地"
        }
    }
}

// MARK: - Rule

struct Rule: Codable, Identifiable, Equatable {
    var id: UUID
    var ssid: String
    var mode: IPv6Mode

    init(id: UUID = UUID(), ssid: String, mode: IPv6Mode) {
        self.id   = id
        self.ssid = ssid
        self.mode = mode
    }
}
