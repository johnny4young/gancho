import GanchoDesign
import GanchoKit
import SwiftUI

/// The iPhone history's composable type + source-app filter. Keeping this
/// presentation component separate leaves `CaptureView` as the flow owner
/// without letting another menu push that coordinator past its lint budget.
struct HistoryFilterMenu: View {
    @Binding var kindFilter: ClipContentKind?
    @Binding var selectedSourceAppBundleID: String?
    let sourceApps: [ClipSourceApp]

    var body: some View {
        Menu {
            if !sourceApps.isEmpty {
                Section("Apps") {
                    Button {
                        selectedSourceAppBundleID = nil
                    } label: {
                        Label("All apps", systemImage: "square.grid.2x2")
                    }
                    ForEach(sourceApps) { app in
                        sourceAppButton(app)
                    }
                }
            }
            Section {
                Picker("Filter by type", selection: $kindFilter) {
                    Text("All types").tag(ClipContentKind?.none)
                    ForEach(ClipContentKind.allCases, id: \.self) { kind in
                        Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
                            .tag(ClipContentKind?.some(kind))
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(Text("Filters"))
        .accessibilityIdentifier("history-filter-menu")
    }

    private func sourceAppButton(_ app: ClipSourceApp) -> some View {
        Button {
            selectedSourceAppBundleID = app.bundleID
        } label: {
            HStack {
                Label(
                    SourceApp.fallbackName(forBundleID: app.bundleID),
                    systemImage: "app.dashed")
                Spacer()
                Text(verbatim: "\(app.clipCount)")
                if selectedSourceAppBundleID == app.bundleID {
                    Image(systemName: "checkmark")
                }
            }
        }
        .accessibilityIdentifier("source-app-\(app.bundleID)")
    }
}
