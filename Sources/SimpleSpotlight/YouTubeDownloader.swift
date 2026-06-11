import AppKit
import Foundation

enum YouTubeDownloadKind: String, Equatable {
    case mp3
    case subtitle
}

enum YouTubeDownloadState: Equatable {
    case idle
    case downloading(URL, YouTubeDownloadKind)
    case finished(URL, YouTubeDownloadKind, URL)
    case failed(URL, YouTubeDownloadKind, String)
}

@MainActor
final class YouTubeDownloader: ObservableObject {
    @Published private(set) var state: YouTubeDownloadState = .idle
    private var activeURL: URL?
    private var activeKind: YouTubeDownloadKind?
    private var task: Task<Void, Never>?

    func downloadIfNeeded(_ url: URL, kind: YouTubeDownloadKind) {
        guard activeURL != url || activeKind != kind else { return }
        activeURL = url
        activeKind = kind
        state = .downloading(url, kind)

        task?.cancel()
        task = Task { [weak self] in
            do {
                let fileURL = try await Self.runDownload(url, kind: kind)
                await MainActor.run {
                    self?.state = .finished(url, kind, fileURL)
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            } catch {
                await MainActor.run {
                    self?.state = .failed(url, kind, error.localizedDescription)
                }
            }
        }
    }

    func reset() {
        activeURL = nil
        activeKind = nil
        state = .idle
    }

    private nonisolated static func runDownload(_ url: URL, kind: YouTubeDownloadKind) async throws -> URL {
        switch kind {
        case .mp3:
            return try await runMP3Download(url)
        case .subtitle:
            return try await runSubtitleDownload(url)
        }
    }

    private nonisolated static func runMP3Download(_ url: URL) async throws -> URL {
        try await runProcess(arguments: [
            "yt-dlp",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "--paths", downloadsDirectory.path,
            "-o", "%(title).200B.%(ext)s",
            "--print", "after_move:filepath",
            url.absoluteString
        ]) { stdout, _ in
            if let path = stdout
                .split(separator: "\n")
                .map(String.init)
                .last(where: { $0.lowercased().hasSuffix(".mp3") }) {
                return URL(fileURLWithPath: path)
            }
            return downloadsDirectory
        }
    }

    private nonisolated static func runSubtitleDownload(_ url: URL) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simple-spotlight-subtitles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let subtitleFile = try await runProcess(arguments: [
            "yt-dlp",
            "--skip-download",
            "--write-subs",
            "--write-auto-subs",
            "--sub-langs", "en.*,ja.*,en,ja",
            "--sub-format", "vtt/best",
            "--paths", tempDirectory.path,
            "-o", "%(title).200B.%(ext)s",
            "--print", "after_move:filepath",
            url.absoluteString
        ]) { stdout, _ in
            let printed = stdout
                .split(separator: "\n")
                .map(String.init)
                .map(URL.init(fileURLWithPath:))
                .first(where: { $0.pathExtension.lowercased() == "vtt" || $0.pathExtension.lowercased() == "srt" })

            if let printed {
                return printed
            }

            let files = (try? FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            if let found = files.first(where: { ["vtt", "srt"].contains($0.pathExtension.lowercased()) }) {
                return found
            }

            throw DownloadError.failed("No subtitles found")
        }

        let raw = try String(contentsOf: subtitleFile, encoding: .utf8)
        let text = subtitleFile.pathExtension.lowercased() == "srt" ? srtToText(raw) : vttToText(raw)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DownloadError.failed("Subtitle file was empty")
        }

        let outputName = subtitleFile
            .deletingPathExtension()
            .deletingPathExtension()
            .lastPathComponent
        let outputURL = uniqueFileURL(
            in: downloadsDirectory,
            baseName: outputName.isEmpty ? "youtube-subtitles" : outputName,
            extension: "txt"
        )
        try text.write(to: outputURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: tempDirectory)
        return outputURL
    }

    private nonisolated static func runProcess<T>(
        arguments: [String],
        parse: @escaping @Sendable (String, String) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
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

                do {
                    continuation.resume(returning: try parse(stdout, stderr))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private nonisolated static var downloadsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    private nonisolated static func uniqueFileURL(in directory: URL, baseName: String, extension fileExtension: String) -> URL {
        let safeBaseName = baseName.replacingOccurrences(of: "/", with: "-")
        var candidate = directory.appendingPathComponent(safeBaseName).appendingPathExtension(fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(safeBaseName) \(index)").appendingPathExtension(fileExtension)
            index += 1
        }
        return candidate
    }

    private nonisolated static func vttToText(_ input: String) -> String {
        subtitleLines(from: input) { line in
            !line.hasPrefix("WEBVTT") &&
                !line.contains("-->") &&
                !line.hasPrefix("Kind:") &&
                !line.hasPrefix("Language:") &&
                !line.trimmingCharacters(in: .decimalDigits).isEmpty
        }
    }

    private nonisolated static func srtToText(_ input: String) -> String {
        subtitleLines(from: input) { line in
            !line.contains("-->") &&
                Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) == nil
        }
    }

    private nonisolated static func subtitleLines(from input: String, include: (String) -> Bool) -> String {
        var previous = ""
        return input
            .components(separatedBy: .newlines)
            .map { stripSubtitleMarkup($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && include($0) }
            .filter { line in
                defer { previous = line }
                return line != previous
            }
            .joined(separator: "\n")
    }

    private nonisolated static func stripSubtitleMarkup(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
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
