import Foundation

struct AppLearningStore {
    private struct Entry: Codable {
        var score: Double
        var lastUsed: TimeInterval
    }

    private let defaults: UserDefaults
    private let key = "appLearning.v1"
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func score(for query: String, appURL: URL) -> Double {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return 0 }
        return table()[normalizedQuery]?[appURL.path]?.score ?? 0
    }

    func record(query: String, appURL: URL) {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return }

        let prefixes = normalized.indices.map { String(normalized[...$0]) }
        let timestamp = now().timeIntervalSince1970
        var data = table()

        for prefix in prefixes {
            var bucket = data[prefix, default: [:]]
            var entry = bucket[appURL.path] ?? Entry(score: 0, lastUsed: timestamp)
            entry.score = min(entry.score + weight(for: prefix, fullQuery: normalized), 50)
            entry.lastUsed = timestamp
            bucket[appURL.path] = entry
            data[prefix] = bucket
        }

        save(data)
    }

    private func weight(for prefix: String, fullQuery: String) -> Double {
        prefix == fullQuery ? 1.25 : 1.0
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func table() -> [String: [String: Entry]] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: Entry]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ table: [String: [String: Entry]]) {
        guard let data = try? JSONEncoder().encode(table) else { return }
        defaults.set(data, forKey: key)
    }
}
