import Testing
import Foundation
@testable import AutoV6

@Suite("RuleStore Tests")
struct RuleStoreTests {

    // Use a unique suite key so tests don't pollute the real UserDefaults
    private func makeStore() -> RuleStore {
        let store = RuleStore(defaultsKey: "AutoV6RulesTest_\(UUID().uuidString)")
        return store
    }

    @Test("Add rule increases count")
    func addRule() {
        let store = makeStore()
        #expect(store.rules.isEmpty)
        store.add(Rule(ssid: "HomeWiFi", mode: .automatic))
        #expect(store.rules.count == 1)
    }

    @Test("Delete rule by id")
    func deleteRule() {
        let store = makeStore()
        let rule = Rule(ssid: "TestNet", mode: .manual)
        store.add(rule)
        store.delete(id: rule.id)
        #expect(store.rules.isEmpty)
    }

    @Test("Update rule changes mode")
    func updateRule() {
        let store = makeStore()
        var rule = Rule(ssid: "TestNet", mode: .manual)
        store.add(rule)
        rule.mode = .linkLocal
        store.update(rule)
        #expect(store.rules.first?.mode == .linkLocal)
    }

    @Test("Match returns correct mode on hit")
    func matchHit() {
        let store = makeStore()
        store.add(Rule(ssid: "CompanyNet", mode: .linkLocal))
        #expect(store.match(ssid: "CompanyNet") == .linkLocal)
    }

    @Test("Match returns nil on miss")
    func matchMiss() {
        let store = makeStore()
        store.add(Rule(ssid: "HomeWiFi", mode: .automatic))
        #expect(store.match(ssid: "UnknownSSID") == nil)
    }

    @Test("Match is case-sensitive exact")
    func matchCaseSensitive() {
        let store = makeStore()
        store.add(Rule(ssid: "HomeWiFi", mode: .automatic))
        #expect(store.match(ssid: "homewifi") == nil)
        #expect(store.match(ssid: "HomeWiFi") == .automatic)
    }

    @Test("Delete all at offsets")
    func deleteAtOffsets() {
        let store = makeStore()
        store.add(Rule(ssid: "A", mode: .automatic))
        store.add(Rule(ssid: "B", mode: .manual))
        store.add(Rule(ssid: "C", mode: .linkLocal))
        store.deleteAll(at: IndexSet([0, 2]))
        #expect(store.rules.count == 1)
        #expect(store.rules.first?.ssid == "B")
    }
}
