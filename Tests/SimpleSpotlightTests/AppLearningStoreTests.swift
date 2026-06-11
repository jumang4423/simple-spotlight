import Foundation
import Testing
@testable import SimpleSpotlight

@Suite
struct AppLearningStoreTests {
    @Test
    func recordsEveryQueryPrefix() {
        let suiteName = "AppLearningStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppLearningStore(defaults: defaults)
        let brave = URL(fileURLWithPath: "/Applications/Brave Browser.app")

        store.record(query: "br", appURL: brave)

        #expect(store.score(for: "b", appURL: brave) > 0)
        #expect(store.score(for: "br", appURL: brave) > store.score(for: "b", appURL: brave))
    }

    @Test
    func normalizesWhitespaceAndCase() {
        let suiteName = "AppLearningStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppLearningStore(defaults: defaults)
        let brave = URL(fileURLWithPath: "/Applications/Brave Browser.app")

        store.record(query: " BR ", appURL: brave)

        #expect(store.score(for: "b", appURL: brave) > 0)
        #expect(store.score(for: "BR", appURL: brave) > 0)
    }
}
