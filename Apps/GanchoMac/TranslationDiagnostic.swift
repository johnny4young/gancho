#if DEBUG
    import Foundation
    import GanchoAI
    import GanchoAppCore
    import OSLog

    nonisolated enum TranslationDiagnostic {
        static var engines: TranslationEngines {
            let base = TranslationUITestFixture.engines
            return TranslationEngines(
                identifySource: { text in
                    phase("fixture-source")
                    return base.identifySource(text)
                },
                pairStatus: { source, target in
                    phase("fixture-pair-entered")
                    let status = await base.pairStatus(source, target)
                    phase("fixture-pair-returned")
                    return status
                },
                native: { text, source, target in
                    phase("fixture-native-entered")
                    let result = try await base.native(text, source, target)
                    phase("fixture-native-returned")
                    DispatchQueue.main.async { phase("dispatch-main-resumed") }
                    return result
                },
                languageModel: base.languageModel, modelAvailable: base.modelAvailable)
        }

        static func phase(_ phase: String) {
            let arguments = CommandLine.arguments
            guard arguments.contains("-use-temp-durable-store"),
                arguments.contains("-ui-test-installed-translation"),
                let index = arguments.firstIndex(of: "-translation-diagnostic-nonce"),
                arguments.indices.contains(index + 1),
                let nonce = UUID(uuidString: arguments[index + 1])
            else { return }
            Logger(
                subsystem: "com.johnny4young.gancho.translation-diagnostic", category: "lifecycle"
            ).notice(
                "request \(nonce.uuidString, privacy: .public) uptime \(ProcessInfo.processInfo.systemUptime, privacy: .public) phase \(phase, privacy: .public) priority \(Task.currentPriority.rawValue, privacy: .public)"
            )
        }
    }
#endif
