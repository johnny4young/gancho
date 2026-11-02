import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// A pending template insertion: the snippet, its resolved body, and the
/// {fields} and {date}s to settle before paste.
struct SnippetFillRequest: Identifiable {
    let snippet: ClipItem
    let body: String
    let fields: [SnippetTemplate.Field]
    let dateOffsets: [Int]
    var id: UUID { snippet.id }

    init(snippet: ClipItem, body: String) {
        self.snippet = snippet
        self.body = body
        fields = SnippetTemplate.fields(in: body)
        dateOffsets = SnippetTemplate.dateOffsets(in: body)
    }
}

/// Collects values for a template snippet's {fields} before paste. Defaults
/// (`{name:World}`) pre-fill the editors; a live preview shows the filled
/// result without reading the clipboard. Keyboard-first: the first field
/// focuses on appear, ⏎ inserts and Esc cancels.
struct SnippetFillSheet: View {
    let request: SnippetFillRequest
    let onInsert: ([String: String], [Int: Date]) -> Void
    let onCancel: () -> Void
    @Environment(\.panelTypeScale) private var typeScale
    @State private var values: [String: String] = [:]
    @State private var dates: [Int: Date] = [:]
    @FocusState private var focusedField: String?

    private var filled: String {
        SnippetTemplate.render(
            request.body, values: values, dates: dates, keepingDeferred: true
        ).text
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
                    ForEach(request.dateOffsets, id: \.self) { dayOffset in
                        dateRow(dayOffset)
                    }
                }
            }
            .frame(height: min(CGFloat(rowCount) * 56 * typeScale, 260 * typeScale))
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
                Button("Insert") { onInsert(values, dates) }
                    .keyboardShortcut(.defaultAction)
                    .ganchoButtonStyle(.primary)
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

    private var rowCount: Int { request.fields.count + request.dateOffsets.count }

    private func dateRow(_ dayOffset: Int) -> some View {
        let label = SnippetTemplate.dateLabel(dayOffset: dayOffset)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .panelFont(.caption, design: .monospaced).foregroundStyle(.secondary)
            DatePicker(
                selection: Binding(
                    get: { dates[dayOffset] ?? SnippetTemplate.defaultDate(dayOffset: dayOffset) },
                    set: { dates[dayOffset] = $0 }),
                displayedComponents: .date
            ) {
                Text(verbatim: label)
            }
            .labelsHidden()
            .accessibilityIdentifier("fill-date-\(dayOffset)")
        }
    }

    private func binding(for field: SnippetTemplate.Field) -> Binding<String> {
        Binding(
            get: { values[field.name] ?? "" },
            set: { values[field.name] = $0 })
    }
}
