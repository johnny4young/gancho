import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// A pending template insertion: the snippet, its resolved body, and the
/// {fields} to fill before paste.
struct SnippetFillRequest: Identifiable {
    let snippet: ClipItem
    let body: String
    let fields: [SnippetTemplate.Field]
    var id: UUID { snippet.id }
}

/// Collects values for a template snippet's {fields} before paste. Defaults
/// (`{name:World}`) pre-fill the editors; a live preview shows the filled
/// result. Keyboard-first: the first field focuses on appear, ⏎ inserts and
/// Esc cancels.
struct SnippetFillSheet: View {
    let request: SnippetFillRequest
    let onInsert: ([String: String]) -> Void
    let onCancel: () -> Void
    @Environment(\.panelTypeScale) private var typeScale
    @State private var values: [String: String] = [:]
    @FocusState private var focusedField: String?

    private var filled: String {
        SnippetTemplate.fill(request.body, values: values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Insert snippet").panelFont(.caption).foregroundStyle(.secondary)
                Text(
                    verbatim: request.snippet.title.isEmpty
                        ? request.snippet.preview : request.snippet.title
                )
                .panelFont(.headline).lineLimit(1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                    ForEach(request.fields) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: field.name)
                                .panelFont(.caption, design: .monospaced).foregroundStyle(
                                    .secondary)
                            TextField(field.defaultValue ?? field.name, text: binding(for: field))
                                .textFieldStyle(.roundedBorder)
                                .panelFont(.body)
                                .focused($focusedField, equals: field.name)
                                .accessibilityIdentifier("fill-field-\(field.name)")
                        }
                    }

                }
            }
            .frame(height: min(CGFloat(request.fields.count) * 56 * typeScale, 260 * typeScale))
            .accessibilityIdentifier("fill-fields-scroll")

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview").panelFont(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    Text(ClipTextPreview.truncated(filled, limit: 4_000))
                        .panelFont(.body, design: .monospaced)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(GanchoTokens.Spacing.xs)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous))
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { onInsert(values) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fill-insert")
            }
        }
        .padding(GanchoTokens.Spacing.lg)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snippet-fill-sheet")
        .onAppear {
            for field in request.fields where field.defaultValue != nil {
                values[field.name] = field.defaultValue
            }
            focusedField = request.fields.first?.name
        }
    }

    private func binding(for field: SnippetTemplate.Field) -> Binding<String> {
        Binding(
            get: { values[field.name] ?? "" },
            set: { values[field.name] = $0 })
    }
}
