import AppKit
import Foundation

enum YouTubeDownloadState: Equatable {
    case idle
    case downloading(URL)
    case finished(URL, URL)
    case failed(URL, String)
}

@MainActor
final class YouTubeDownloader: ObservableObject {
    @Published private(set) var state: YouTubeDownloadState = .idle
    private var activeURL: URL?
    private var task: Task<Void, Never>?

    func downloadIfNeeded(_ url: URL) {
        guard activeURL != url else { return }
        activeURL = url
        state = .downloading(url)

        task?.cancel()
        task = Task { [weak self] in
            do {
                let fileURL = try await Self.runDownload(url)
                await MainActor.run {
                    self?.state = .finished(url, fileURL)
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            } catch {
                await MainActor.run {
                    self?.state = .failed(url, error.localizedDescription)
                }
            }
        }
    }

    func reset() {
        activeURL = nil
        state = .idle
    }

    private nonisolated static func runDownload(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "yt-dlp",
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--paths", downloads.path,
                "-o", "%(title).200B.%(ext)s",
                "--print", "after_move:filepath",
                url.absoluteString
            ]
            process.environment = [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            ]

            let output = Pipe()
            let errorOutput = Pipe()
            process.standardOutput = output
            process.standardError = errorOutput

            process.terminationHandler = { process in
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: DownloadError.failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }

                if let path = stdout
                    .split(separator: "\n")
                    .map(String.init)
                    .last(where: { $0.lowercased().hasSuffix(".mp3") }) {
                    continuation.resume(returning: URL(fileURLWithPath: path))
                } else {
                    continuation.resume(returning: downloads)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum DownloadError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message.isEmpty ? "Download failed" : message
        }
    }
}
