import AppKit
import Foundation

struct LauncherApp: Identifiable, Equatable {
    let id: URL
    let name: String
    let url: URL
}

final class ApplicationStore {
    private let apps: [LauncherApp]

    init() {
        apps = Self.scanApplications()
    }

    func search(_ query: String, limit: Int = 8) -> [LauncherApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        return apps.compactMap { app -> (LauncherApp, Int)? in
            let haystack = app.name.lowercased()
            if haystack == needle { return (app, 0) }
            if haystack.hasPrefix(needle) { return (app, 1) }
            if haystack.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return (app, 2) }
            if haystack.contains(needle) { return (app, 3) }
            return nil
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
    }

    func open(_ app: LauncherApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func scanApplications() -> [LauncherApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var seen = Set<URL>()
        var result: [LauncherApp] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard !seen.contains(url) else { continue }
                seen.insert(url)

                let name = displayName(for: url)
                result.append(LauncherApp(id: url, name: name, url: url))
            }
        }

        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
