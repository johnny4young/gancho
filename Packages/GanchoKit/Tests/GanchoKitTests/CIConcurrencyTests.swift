import Foundation
import Testing

@Suite("CI post-merge concurrency")
struct CIConcurrencyTests {
    @Test("Three pushes retain the code merge when a later merge only changes docs")
    func pushesRetainEveryMerge() throws {
        let source = try workflow()
        let policy = try Policy(source: source)
        let codeChanged = try appChanged(["Apps/GanchoiOS/CaptureView.swift"], in: source)
        let docsChanged = try appChanged(["README.md", "docs/guide.md"], in: source)
        #expect(codeChanged)
        #expect(!docsChanged)
        #expect(source.contains("push) endpoint=\"compare/$BEFORE...$AFTER\""))
        #expect(
            source.contains(
                "if: github.event_name != 'pull_request' && needs.changes.outputs.app == 'true'"))

        // Model GitHub's default one-running/one-pending rule, not hosted timing.
        // A is already running; B changes code; C's before is B and only adds docs.
        let pushes = try [101, 102, 103].map {
            try policy.group(event: "push", ref: "refs/heads/main", runID: $0)
        }
        var queue = Queue()
        for (index, group) in pushes.enumerated() {
            queue.enqueue(run: index, group: group, cancel: policy.cancel(event: "push"))
        }
        #expect(Set(pushes).count == 3)
        #expect(queue.cancelled.isEmpty)
        #expect(queue.retained.contains(1), "B must retain its post-merge iOS validation")

        // Control: false only protects A. Reusing the branch group drops pending B.
        var sharedGroup = Queue()
        for run in 0..<3 {
            sharedGroup.enqueue(run: run, group: "ci-refs/heads/main", cancel: false)
        }
        #expect(sharedGroup.cancelled == [1])
        #expect(sharedGroup.retained == [0, 2])
    }

    @Test("Synchronizations of the same PR still cancel; different PRs stay separate")
    func pullRequestsSupersedeOnlyThemselves() throws {
        let policy = try Policy(source: workflow())
        let first = try policy.group(event: "pull_request", ref: "refs/pull/7/merge", runID: 201)
        let next = try policy.group(event: "pull_request", ref: "refs/pull/7/merge", runID: 202)
        let other = try policy.group(event: "pull_request", ref: "refs/pull/8/merge", runID: 203)
        #expect(first == next)
        #expect(first != other)
        #expect(policy.cancel(event: "pull_request"))
        var queue = Queue()
        queue.enqueue(run: 0, group: first, cancel: policy.cancel(event: "pull_request"))
        queue.enqueue(run: 1, group: next, cancel: policy.cancel(event: "pull_request"))
        queue.enqueue(run: 2, group: other, cancel: policy.cancel(event: "pull_request"))
        #expect(queue.cancelled == [0])
        #expect(queue.retained == [1, 2])
    }

    @Test(arguments: ["push", "schedule", "workflow_dispatch"])
    func nonPRRunsDoNotCancelInProgress(event: String) throws {
        let policy = try Policy(source: workflow())
        #expect(!policy.cancel(event: event))
    }

    private struct Policy {
        let template: String

        init(source: String) throws {
            let start = try #require(source.range(of: "\nconcurrency:\n"))
            let end = try #require(
                source.range(of: "\njobs:", range: start.upperBound..<source.endIndex))
            let block = String(source[start.upperBound..<end.lowerBound])
            let line = try #require(
                block.split(separator: "\n").first { $0.hasPrefix("  group: ") })
            template = String(line.dropFirst("  group: ".count))
            #expect(
                block.contains("cancel-in-progress: ${{ github.event_name == 'pull_request' }}"))
            #expect(!block.contains("queue:"), "the model covers the default single pending slot")
        }

        func group(event: String, ref: String, runID: Int) throws -> String {
            // Deliberately limited expression rendering: fail on unmodelled syntax.
            let result = template.replacingOccurrences(
                of: "${{ github.event_name == 'push' && github.run_id || github.ref }}",
                with: event == "push" ? String(runID) : ref
            ).replacingOccurrences(of: "${{ github.ref }}", with: ref)
            try #require(
                !result.contains("${{"), "Extend the concurrency model for new expressions")
            return result.lowercased()
        }

        func cancel(event: String) -> Bool { event == "pull_request" }
    }

    private struct Queue {
        var running: [String: Int] = [:]
        var pending: [String: Int] = [:]
        var cancelled: Set<Int> = []
        var retained: Set<Int> { Set(running.values).union(pending.values) }

        mutating func enqueue(run: Int, group: String, cancel: Bool) {
            if let old = pending.removeValue(forKey: group) { cancelled.insert(old) }
            if let old = running[group] {
                if cancel {
                    cancelled.insert(old)
                    running[group] = run
                } else {
                    pending[group] = run
                }
            } else {
                running[group] = run
            }
        }
    }

    private func appChanged(_ files: [String], in source: String) throws -> Bool {
        let start = try #require(source.range(of: "          app=false\n"))
        let end = try #require(
            source.range(of: "          echo \"$files\"", range: start.upperBound..<source.endIndex)
        )
        let script = String(source[start.lowerBound..<end.lowerBound])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Execute only the real path classifier, never gh, providers or app code.
        process.arguments = ["-c", script + "\nprintf '%s' \"$app\""]
        process.environment = ["files": files.joined(separator: "\n"), "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        let value = try #require(String(data: data, encoding: .utf8))
        try #require(value == "true" || value == "false")
        return value == "true"
    }

    private func workflow() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
    }
}
