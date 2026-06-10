import AppKit
import SwiftUI

enum SpotlightResult: Identifiable, Equatable {
    case app(LauncherApp)
    case calculation(String)

    var id: String {
        switch self {
        case .app(let app): return app.url.path
        case .calculation(let value): return "calc-\(value)"
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

    init(appStore: ApplicationStore, calculator: Calculator) {
        self.appStore = appStore
        self.calculator = calculator
    }

    func reset() {
        query = ""
        results = []
        selectionIndex = 0
    }

    func requestFocus() {
        focusToken = UUID()
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectionIndex = min(max(selectionIndex + delta, 0), results.count - 1)
    }

    func executeSelected() {
        guard results.indices.contains(selectionIndex) else { return }
        if case .app(let app) = results[selectionIndex] {
            appStore.open(app)
        }
    }

    private func refresh() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
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
                viewModel.executeSelected()
                close()
            }, focusToken: viewModel.focusToken)
            .frame(height: 74)
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 4)

            if !viewModel.results.isEmpty {
                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 22)
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == viewModel.selectionIndex)
                            .frame(height: 54)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 680)
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
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 32, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = ""
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

private struct ResultRow: View {
    let result: SpotlightResult
    let isSelected: Bool

    var body: some View {
        ZStack {
            selectionBackground
                .padding(.vertical, 5)

            HStack(spacing: 12) {
                icon
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
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
        }
    }

    private var subtitle: String {
        switch result {
        case .app: return "Application"
        case .calculation: return "Calculator"
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
