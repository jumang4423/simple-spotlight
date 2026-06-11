import AppKit
import Combine
import SwiftUI

enum SpotlightResult: Identifiable, Equatable {
    case app(LauncherApp)
    case calculation(String)
    case youtubeDownload(URL, String, Bool)

    var id: String {
        switch self {
        case .app(let app): return app.url.path
        case .calculation(let value): return "calc-\(value)"
        case .youtubeDownload(let url, let value, let isLoading): return "youtube-\(url.absoluteString)-\(value)-\(isLoading)"
        }
    }
}

@MainActor
final class SpotlightViewModel: ObservableObject {
    @Published var query = "" {
        didSet { refresh() }
    }
    @Published private(set) var results: [SpotlightResult] = []
    @Published var selectionIndex = 0
    @Published var focusToken = UUID()

    private let appStore: ApplicationStore
    private let calculator: Calculator
    private let downloader: YouTubeDownloader
    private var cancellables = Set<AnyCancellable>()

    init(appStore: ApplicationStore, calculator: Calculator, downloader: YouTubeDownloader) {
        self.appStore = appStore
        self.calculator = calculator
        self.downloader = downloader
        downloader.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func reset() {
        query = ""
        results = []
        selectionIndex = 0
        downloader.reset()
    }

    func requestFocus() {
        focusToken = UUID()
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectionIndex = min(max(selectionIndex + delta, 0), results.count - 1)
    }

    @discardableResult
    func executeSelected() -> Bool {
        guard results.indices.contains(selectionIndex) else { return false }
        switch results[selectionIndex] {
        case .app(let app):
            appStore.open(app)
            return true
        case .youtubeDownload(let url, _, _):
            downloader.downloadIfNeeded(url)
            results = [youtubeResult(for: url)]
            return false
        case .calculation:
            return false
        }
    }

    private func refresh() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            selectionIndex = 0
            return
        }

        if let youtubeURL = youtubeURL(from: trimmed) {
            results = [youtubeResult(for: youtubeURL)]
            selectionIndex = 0
            return
        }

        var next = appStore.search(trimmed).map(SpotlightResult.app)
        if let value = calculator.evaluate(trimmed) {
            next.insert(.calculation(format(value)), at: 0)
        }
        results = next
        selectionIndex = min(selectionIndex, max(next.count - 1, 0))
    }

    private func youtubeURL(from input: String) -> URL? {
        guard let url = URL(string: input),
              let host = url.host?.lowercased(),
              host == "youtu.be" || host.hasSuffix("youtube.com"),
              input.lowercased().hasPrefix("http") else {
            return nil
        }
        return url
    }

    private func youtubeResult(for url: URL) -> SpotlightResult {
        switch downloader.state {
        case .idle:
            return .youtubeDownload(url, "yt-dlp mp3", false)
        case .downloading(let activeURL) where activeURL == url:
            return .youtubeDownload(url, "Downloading MP3 to Downloads...", true)
        case .downloading:
            return .youtubeDownload(url, "yt-dlp mp3", false)
        case .finished(let file):
            return .youtubeDownload(url, "Downloaded \(file.lastPathComponent)", false)
        case .failed(let message):
            return .youtubeDownload(url, "Download failed: \(message)", false)
        }
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int64(value))
        }
        return String(format: "%.10g", value)
    }
}

struct SpotlightView: View {
    @ObservedObject var viewModel: SpotlightViewModel
    let close: () -> Void
    private let panelRadius: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            FocusedSearchField(text: $viewModel.query, onSubmit: {
                if viewModel.executeSelected() {
                    close()
                }
            }, focusToken: viewModel.focusToken)
            .frame(height: 64)
            .padding(.horizontal, 24)
            .padding(.top, 3)
            .padding(.bottom, 3)

            if !viewModel.results.isEmpty {
                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 22)
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == viewModel.selectionIndex)
                            .frame(height: 48)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 620)
        .liquidGlassPanel(radius: panelRadius)
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelection(1)
            return .handled
        }
    }
}

private struct FocusedSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let focusToken: UUID

    func makeNSView(context: Context) -> NSTextField {
        let field = PasteFriendlyTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 28, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = "jumango ai..."
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void
        var focusToken: UUID?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        @objc func submit() {
            onSubmit()
        }
    }
}

private final class PasteFriendlyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "v":
            currentEditor()?.paste(nil)
            return true
        case "c":
            currentEditor()?.copy(nil)
            return true
        case "x":
            currentEditor()?.cut(nil)
            return true
        case "a":
            currentEditor()?.selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private struct ResultRow: View {
    let result: SpotlightResult
    let isSelected: Bool

    var body: some View {
        ZStack {
            selectionBackground
                .padding(.vertical, 5)

            HStack(spacing: 12) {
            icon
                .frame(width: 27, height: 27)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        } else {
            Color.clear
        }
    }

    private var title: String {
        switch result {
        case .app(let app): return app.name
        case .calculation(let value): return value
        case .youtubeDownload(_, let value, _): return value
        }
    }

    private var subtitle: String {
        switch result {
        case .app: return "Application"
        case .calculation: return "Calculator"
        case .youtubeDownload(_, _, let isLoading):
            return isLoading ? "Please wait" : "Select to download to Downloads"
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .app(let app):
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .calculation:
            Image(systemName: "function")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        case .youtubeDownload(_, _, let isLoading):
            YouTubeIcon(isLoading: isLoading)
        }
    }
}

private struct YouTubeIcon: View {
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: URL(string: "https://www.youtube.com/favicon.ico")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                default:
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 24, height: 24)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.72)
                    .offset(x: 5, y: 5)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassPanel(radius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            background(.regularMaterial)
        }
    }
}
