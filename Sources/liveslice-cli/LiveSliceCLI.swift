// Why: the one real caller of LiveSliceCore today. It exists so the DeepSeek path is exercised
// end-to-end (scripts/live_check.sh) instead of only in offline tests. Usage:
//   liveslice-cli slice <input.srt> [--out <edl.json>]
// Exit codes: 0 success, 1 pipeline error (message on stderr), 2 usage / missing API key.

import Foundation
import LiveSliceCore

@main
struct LiveSliceCLI {
    static func main() async {
        do {
            let (input, output) = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            let configuration = try DeepSeekConfiguration.fromEnvironment(ProcessInfo.processInfo.environment)
            let srtText = try String(contentsOfFile: input, encoding: .utf8)
            let slicer = TopicSlicer(client: DeepSeekClient(configuration: configuration))
            let document = try await slicer.slice(srtText: srtText)
            let json = try document.encode()
            if let output {
                try json.write(to: URL(fileURLWithPath: output))
            } else {
                print(String(decoding: json, as: UTF8.self))
            }
            print(summary(document, model: configuration.model, output: output))
        } catch DeepSeekError.missingAPIKey {
            fail("DEEPSEEK_API_KEY is not set. Export it in your shell; this tool has no offline/demo mode.", code: 2)
        } catch let error as UsageError {
            fail(error.message, code: 2)
        } catch {
            fail("slice failed: \(error)", code: 1)
        }
    }

    struct UsageError: Error {
        let message: String
    }

    static func parseArguments(_ args: [String]) throws -> (input: String, output: String?) {
        guard args.first == "slice", args.count >= 2 else {
            throw UsageError(message: "usage: liveslice-cli slice <input.srt> [--out <edl.json>]")
        }
        var output: String?
        var index = 2
        while index < args.count {
            guard args[index] == "--out", index + 1 < args.count else {
                throw UsageError(message: "unknown or incomplete argument: \(args[index])")
            }
            output = args[index + 1]
            index += 2
        }
        return (args[1], output)
    }

    static func summary(_ document: EDLDocument, model: String, output: String?) -> String {
        var lines = [
            "schema_version=\(document.schemaVersion) model=\(model) clips=\(document.clips.count) "
                + "policy=\(document.clipCountPolicy.minClips)~\(document.clipCountPolicy.maxClips) "
                + "(hard \(document.clipCountPolicy.hardMaxClips), \(document.clipCountPolicy.durationMinutes) min)",
        ]
        if let llm = document.llm {
            lines.append(
                "tokens: prompt=\(llm.promptTokens) completion=\(llm.completionTokens) total=\(llm.totalTokens) "
                    + "latency=\(llm.latencyMs)ms"
            )
        }
        for clip in document.clips {
            var line = "  \(clip.id) \(clip.start)-\(clip.end) score=\(clip.score) segments=\(clip.segments.count)"
                + " kept=\(Int(clip.keptDurationSec))s"
            if let category = clip.category { line += " [\(category)]" }
            lines.append(line + " \(clip.title)")
        }
        if let output { lines.append("written: \(output)") }
        return lines.joined(separator: "\n")
    }

    static func fail(_ message: String, code: Int32) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(code)
    }
}
