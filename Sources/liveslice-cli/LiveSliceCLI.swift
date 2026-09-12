// Why: the one real caller of LiveSliceCore today. It exists so the DeepSeek path is exercised
// end-to-end (scripts/live_check.sh) instead of only in offline tests. Usage:
//   liveslice-cli slice <input.srt> [--out <edl.json>] [--domain <general|military_news|...>]
// Exit codes: 0 success, 1 pipeline error (message on stderr), 2 usage / missing API key.

import Foundation
import LLMKit
import LiveSliceCore

@main
struct LiveSliceCLI {
    static func main() async {
        do {
            let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            let configuration = try DeepSeekConfiguration.fromEnvironment(ProcessInfo.processInfo.environment)
            let srtText = try String(contentsOfFile: options.input, encoding: .utf8)
            let strategy = SlicingStrategy.topicComplete(domain: options.domain)
            let slicer = TopicSlicer(client: DeepSeekClient(configuration: configuration), strategy: strategy)
            let document = try await slicer.slice(srtText: srtText)
            let json = try document.encode()
            if let output = options.output {
                try json.write(to: URL(fileURLWithPath: output))
            } else {
                print(String(decoding: json, as: UTF8.self))
            }
            print(summary(document, model: configuration.model, output: options.output))
        } catch DeepSeekError.missingAPIKey {
            fail("DEEPSEEK_API_KEY is not set. Export it in your shell; this tool has no offline/demo mode.", code: 2)
        } catch let error as UsageError {
            fail(error.message, code: 2)
        } catch {
            fail("slice failed: \(error)", code: 1)
        }
    }

    struct CLIOptions: Equatable {
        let input: String
        let output: String?
        let domain: String
    }

    struct UsageError: Error {
        let message: String
    }

    static func parseArguments(_ args: [String]) throws -> CLIOptions {
        guard args.first == "slice", args.count >= 2 else {
            throw UsageError(message: "usage: liveslice-cli slice <input.srt> [--out <edl.json>] [--domain <domain>]")
        }
        var output: String?
        var domain = "general"
        var index = 2
        while index < args.count {
            if args[index] == "--out", index + 1 < args.count {
                output = args[index + 1]
                index += 2
            } else if args[index] == "--domain", index + 1 < args.count {
                domain = args[index + 1]
                index += 2
            } else {
                throw UsageError(message: "unknown or incomplete argument: \(args[index])")
            }
        }
        return CLIOptions(input: args[1], output: output, domain: domain)
    }

    static func summary(_ document: EDLDocument, model: String, output: String?) -> String {
        var lines = [
            "schema_version=\(document.schemaVersion) model=\(model) domain=\(document.strategy.domain) clips=\(document.clips.count) "
                + "highlights=\(highlightCount(document)) "
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
        if let highlights = document.highlights {
            for quote in highlights {
                lines.append("  \(quote.id) \(quote.start)-\(quote.end) score=\(quote.score) kept=\(Int(quote.keptDurationSec))s \(quote.title)")
            }
        }
        if let output { lines.append("written: \(output)") }
        return lines.joined(separator: "\n")
    }

    /// "none" for a document written before highlights existed, else the count (0 = model found none).
    static func highlightCount(_ document: EDLDocument) -> String {
        guard let highlights = document.highlights else { return "none" }
        return String(highlights.count)
    }

    static func fail(_ message: String, code: Int32) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(code)
    }
}
