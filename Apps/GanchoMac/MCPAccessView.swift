import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// The local MCP server control surface (the design's "MCP Access" screen): an
/// opt-in toggle, the three EXPOSURE scopes, the four tools agents can call with
/// their read/write reach under the current scope, the sensitive-veto guarantee,
/// and the metadata-only access log. Off by default; every number is local.
struct MCPAccessView: View {
    @Environment(AppModel.self) private var model
    @State private var log: [MCPAccessEvent] = []

    /// Tools the local server exposes. `reads` = the call can return a content
    /// body (so it's gated by scope); writes never expose content.
    private struct Tool: Identifiable {
        let name: MCPToolName
        let symbol: String
        let descriptionKey: LocalizedStringKey
        let reads: Bool
        var id: String { name.rawValue }
    }

    private let tools: [Tool] = [
        .init(
            name: .searchClips, symbol: "magnifyingglass",
            descriptionKey: "Find clips by text query.", reads: true),
        .init(
            name: .getClip, symbol: "doc.text",
            descriptionKey: "Fetch one clip by id.", reads: true),
        .init(
            name: .createPin, symbol: "pin",
            descriptionKey: "Pin a clip or add it to a board.", reads: false),
        .init(
            name: .pasteStack, symbol: "square.stack",
            descriptionKey: "Queue clips into the paste stack.", reads: true),
    ]

    private var enabled: Bool { model.mcpConfig.isEnabled }
    private var exposesBody: Bool { model.mcpConfig.scope != .metadata }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            HStack {
                Label("MCP Access", systemImage: "terminal")
                    .font(.title2.bold())
                Spacer()
                statusBadge
            }

            Form {
                Section {
                    Toggle(
                        "Allow local AI agents (MCP)",
                        isOn: Binding(
                            get: { model.mcpConfig.isEnabled }, set: { model.setMCPEnabled($0) }))
                    Text(
                        "Lets local agents — Claude, Cursor, the gancho CLI — reach your clipboard over a loopback connection. No network, no cloud. Off by default."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Local MCP server")
                }

                Section {
                    Picker(
                        "Access scope",
                        selection: Binding(
                            get: { model.mcpConfig.scope }, set: { model.setMCPScope($0) })
                    ) {
                        Text("Metadata only").tag(MCPAccessScope.metadata)
                        Text("Marked boards only").tag(MCPAccessScope.boards)
                        Text("Everything").tag(MCPAccessScope.all)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!enabled)
                    Text(scopeDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("A narrower scope reveals less clip data — never fewer verbs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } header: {
                    Text("Access scope")
                }

                Section {
                    ForEach(tools) { tool in
                        HStack(spacing: GanchoTokens.Spacing.sm) {
                            Image(systemName: tool.symbol)
                                .foregroundStyle(.secondary).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: tool.name.rawValue).font(.callout.monospaced())
                                Text(tool.descriptionKey)
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            toolBadge(tool)
                        }
                        .opacity(enabled ? 1 : 0.5)
                    }
                } header: {
                    Text("Tools exposed")
                }

                Section {
                    Label {
                        Text(
                            "Sensitive clips are vetoed in every scope, including Everything — an agent never sees a secret the detector flagged."
                        )
                        .font(.footnote)
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(GanchoTokens.Palette.kindTint(for: .secret))
                    }
                }

                Section {
                    if log.isEmpty {
                        Text("No agent access yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, event in
                            logRow(event)
                        }
                    }
                } header: {
                    HStack {
                        Text("Access log")
                        Spacer()
                        Text("Metadata only — never clip content")
                            .font(.caption).foregroundStyle(.tertiary).textCase(nil)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 480, height: 600)
        .accessibilityIdentifier("mcp-access")
        .task { log = await model.recentMCPAccesses(limit: 20) }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(enabled ? GanchoTokens.Palette.success : Color.secondary)
                .frame(width: 7, height: 7)
            if enabled {
                HStack(spacing: 0) {
                    Text("Listening")
                    Text(verbatim: " · 127.0.0.1")
                }
            } else {
                Text("Off")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(enabled ? GanchoTokens.Palette.success : Color.secondary)
    }

    private var scopeDescription: LocalizedStringKey {
        switch model.mcpConfig.scope {
        case .metadata:
            "Titles and sanitized previews only — never a content body. An agent can find clips and pin them, but cannot read what they hold."
        case .boards:
            "Full content, but only for clips you have deliberately marked — pinned or on a board. Raw history stays invisible."
        case .all:
            "Full content of every non-sensitive clip. Sensitive clips remain vetoed, even here."
        }
    }

    @ViewBuilder private func toolBadge(_ tool: Tool) -> some View {
        let (textKey, tint): (LocalizedStringKey, Color) =
            tool.reads
            ? (exposesBody
                ? ("Reads content", GanchoTokens.Palette.success)
                : ("Metadata only", GanchoTokens.Palette.warning))
            : ("Write", .secondary)
        Text(textKey)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func logRow(_ event: MCPAccessEvent) -> some View {
        LabeledContent {
            Text(event.occurredAt, style: .time)
        } label: {
            Label {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Text(verbatim: event.tool.rawValue).monospaced()
                    Text(verbatim: event.scope.rawValue)
                        .font(.caption2).foregroundStyle(.secondary)
                    if event.wasDenied {
                        Text("denied").font(.caption).foregroundStyle(GanchoTokens.Palette.warning)
                    } else if event.resultCount > 0 {
                        Text("\(event.resultCount) clips exposed")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } icon: {
                Image(systemName: event.wasDenied ? "minus.circle" : "checkmark.circle")
                    .foregroundStyle(
                        event.wasDenied
                            ? GanchoTokens.Palette.warning : GanchoTokens.Palette.success)
            }
        }
    }
}

/// Window host for the MCP Access screen (menu-bar agent, no WindowGroup).
@MainActor
final class MCPAccessWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MCPAccessView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "MCP Access")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
