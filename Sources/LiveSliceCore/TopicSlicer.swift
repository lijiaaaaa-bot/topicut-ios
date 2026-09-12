// Why: the single end-to-end use case of v0.1 — SRT text in, validated EDL document out. This is
// the seam a future on-device ASR adapter and renderer plug into (see docs/ARCHITECTURE.yaml
// `planned`); nothing here anticipates them beyond consuming/producing the contract types.

import Foundation
import LLMKit

public enum TopicSlicerError: Error, Equatable, Sendable {
    /// The SRT parsed to zero cues; there is nothing to slice.
    case emptyTranscript
    /// Transcript exceeds the strategy's character budget. Split the input; we do not truncate silently.
    case transcriptTooLong(chars: Int, max: Int)
    /// A clip range falls outside the subtitle time range (beyond ±0.5s tolerance).
    case clipOutOfBounds(clipID: String, startSec: Double, endSec: Double, transcriptStart: Double, transcriptEnd: Double)
}

public struct TopicSlicer: Sendable {
    public static let temperature = 0.3
    private static let boundsToleranceSec = 0.5

    public let client: DeepSeekClient
    public let strategy: SlicingStrategy
    public let taste: SlicingTaste

    public init(
        client: DeepSeekClient, strategy: SlicingStrategy = .topicCompleteGeneral,
        taste: SlicingTaste = .standard
    ) {
        self.client = client
        self.strategy = strategy
        self.taste = taste
    }

    /// Runs the whole vertical slice. Every failure surfaces as a typed error; no partial output.
    public func slice(srtText: String, now: Date = Date()) async throws -> EDLDocument {
        let cues = try SRTParser.parse(srtText)
        guard let firstCue = cues.first, let lastCue = cues.last else { throw TopicSlicerError.emptyTranscript }
        let transcript = SRTParser.plainTranscript(cues)
        guard transcript.count <= strategy.maxTranscriptChars else {
            throw TopicSlicerError.transcriptTooLong(chars: transcript.count, max: strategy.maxTranscriptChars)
        }
        let duration = lastCue.end - firstCue.start
        let policy = try strategy.clipCountPolicy(forDurationSeconds: duration)
        let highlightPolicy = try strategy.highlightCountPolicy(forDurationSeconds: duration)
        let clipped = taste.apply(policy)
        let highlights = taste.apply(highlightPolicy)
        let messages = [
            ChatMessage(
                role: "system",
                content: TopicCompletePrompt.system(policy: clipped, highlights: highlights, domain: strategy.domain)
            ),
            ChatMessage(role: "user", content: "\(TopicCompletePrompt.userIntro(domain: strategy.domain))\n\n\(transcript)"),
        ]
        let reply: ChatCompletionResult = try await client.chatCompletion(messages: messages, temperature: Self.temperature)
        let slices: LLMSlices = try LLMResponseParser.parse(from: reply.content)
        let info = EDLTranscriptInfo(cueCount: cues.count, startSec: firstCue.start, endSec: lastCue.end)
        try Self.checkBounds(slices.clips + slices.highlights, transcript: info)
        return EDLDocument(
            generatedAt: now, strategy: strategy, clipCountPolicy: clipped, transcript: info, clips: slices.clips,
            llm: reply.usage, highlights: slices.highlights, highlightPolicy: highlights
        )
    }

    private static func checkBounds(_ clips: [EDLClip], transcript: EDLTranscriptInfo) throws {
        let lower = transcript.startSec - boundsToleranceSec
        let upper = transcript.endSec + boundsToleranceSec
        for clip in clips {
            guard clip.startSec >= lower, clip.endSec <= upper else {
                throw TopicSlicerError.clipOutOfBounds(
                    clipID: clip.id, startSec: clip.startSec, endSec: clip.endSec,
                    transcriptStart: transcript.startSec, transcriptEnd: transcript.endSec
                )
            }
        }
    }
}
