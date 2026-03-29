import Foundation
import Observation

@Observable
final class RuleStore {

    // MARK: - Stored Properties

    private(set) var rules: [Rule] = []

    private let defaultsKey: String

    // MARK: - Init

    init(defaultsKey: String = "AutoV6Rules") {
        self.defaultsKey = defaultsKey
        load()
    }

    // MARK: - CRUD

    func add(_ rule: Rule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: Rule) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx] = rule
        save()
    }

    func delete(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func deleteAll(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Matching

    /// Returns the IPv6Mode for the given SSID, or nil if no rule matches.
    func match(ssid: String) -> IPv6Mode? {
        rules.first(where: { $0.ssid == ssid })?.mode
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([Rule].self, from: data)
        else { return }
        rules = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
