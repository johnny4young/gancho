import GanchoKit
import SwiftUI

struct SavedFilterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: SmartCollectionRule
    let boards: [Pinboard]
    let save: (SmartCollectionRule) async -> Bool
    @State private var working = false
    @State private var failed = false

    private var invalid: Bool {
        rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (rule.boardID != nil && !boards.contains { $0.id == rule.boardID })
            || (rule.searchMode == .regex
                && (try? NSRegularExpression(pattern: rule.textContains ?? "")) == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved filter").font(.headline)
            ScrollView {
                Form {
                    TextField("Name", text: $rule.name).accessibilityIdentifier("filter-name-field")
                    TextField(
                        "Search",
                        text: Binding(
                            get: { rule.textContains ?? "" }, set: { rule.textContains = $0 })
                    )
                    .accessibilityIdentifier("filter-query-field")
                    Picker(
                        "Search mode",
                        selection: Binding(
                            get: { rule.searchMode ?? .fuzzy }, set: { rule.searchMode = $0 })
                    ) {
                        Text("Prefix matching").tag(ClipSearchQuery.Mode.fuzzy)
                        Text("Exact phrase").tag(ClipSearchQuery.Mode.exact)
                        Text("Regular expression").tag(ClipSearchQuery.Mode.regex)
                    }
                    TextField(
                        "Source application ID",
                        text: Binding(
                            get: { rule.sourceAppBundleID ?? "" },
                            set: { rule.sourceAppBundleID = $0.isEmpty ? nil : $0 }))
                    Picker("Board", selection: $rule.boardID) {
                        Text("All clips").tag(UUID?.none)
                        ForEach(boards) { board in
                            Text(verbatim: board.name).tag(Optional(board.id))
                        }
                        if let id = rule.boardID, !boards.contains(where: { $0.id == id }) {
                            Text("Missing board — choose another").tag(Optional(id))
                        }
                    }
                    Toggle("Pinned only", isOn: $rule.pinnedOnly)
                    DisclosureGroup("Content types") {
                        ForEach(ClipContentKind.allCases, id: \.self) { kind in
                            Toggle(
                                LocalizedStringKey(kind.rawValue),
                                isOn: Binding(
                                    get: { rule.kinds?.contains(kind) ?? true },
                                    set: { included in
                                        var kinds = rule.kinds ?? Set(ClipContentKind.allCases)
                                        if included {
                                            kinds.insert(kind)
                                        } else {
                                            kinds.remove(kind)
                                        }
                                        rule.kinds = kinds
                                    }))
                        }
                    }
                }
            }.frame(maxHeight: 360)
            if failed { Text("Couldn’t save this filter. Try again.").foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    working = true
                    Task {
                        if await save(rule) { dismiss() } else { failed = true }
                        working = false
                    }
                }
                .disabled(working || invalid || rule.kinds?.isEmpty == true)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("filter-confirm")
            }
        }.padding(20).frame(width: 420)
    }
}
