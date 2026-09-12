// Why: LLM output is untrusted text. This is the one place that turns it into validated EDL
// clips; every field the prompt demands is required here, and a bad range is an error rather
// than a silently dropped item (the Python original skipped `start == end` placeholders).
// Locating the JSON object and describing decode failures is `LLMJSON` (LiJiaKit/LLMKit);
// this file owns only the EDL shape and its invariants.

import Foundation
import LLMKit

public enum LLMResponseError: Error, Equatable, Sendable {
    /// No `{ ... }` object could be located in the text.
    case noJSONObject(preview: String)
    /// JSON was found but does not match the expected `frameworks[].slices[]` shape.
    case decoding(String)
    /// Frameworks array was present but empty — the LLM produced no slices.
    case noSlices
}

/// Both products of one slicing call (ADR-0022): topic clips (never empty) and highlights (may be).
public struct LLMSlices: Equatable, Sendable {
    public let clips: [EDLClip]
    public let highlights: [EDLClip]
}

public enum LLMResponseParser {
    /// The framework id every highlight is filed under; ids become `highlights_c_NN`.
    public static let highlightsFrameworkID = "highlights"
    public static let highlightsFrameworkTitle = "金句"

    /// Parses the raw chat response into validated clips and highlights. The `highlights` key is
    /// required (the prompt demands it, empty or not); a reply without it is a decoding error.
    public static func parse(from text: String) throws -> LLMSlices {
        let response: RawResponse
        do {
            response = try LLMJSON.decode(RawResponse.self, from: text)
        } catch let LLMJSONError.noJSONObject(preview) {
            throw LLMResponseError.noJSONObject(preview: preview)
        } catch let LLMJSONError.decoding(detail) {
            throw LLMResponseError.decoding(detail)
        }
        let pairs = response.frameworks.flatMap { framework in framework.slices.map { (framework, $0) } }
        let ids = EDLClip.uniqueIDs(frameworkIDs: pairs.map(\.0.id))
        var clips: [EDLClip] = []
        for (index, (framework, slice)) in pairs.enumerated() {
            clips.append(try makeClip(slice, clipID: ids[index], framework: framework))
        }
        guard !clips.isEmpty else { throw LLMResponseError.noSlices }
        let quoteFramework = RawFramework(id: highlightsFrameworkID, title: highlightsFrameworkTitle, slices: [])
        let quoteIDs = EDLClip.uniqueIDs(frameworkIDs: response.highlights.map { _ in highlightsFrameworkID })
        var highlights: [EDLClip] = []
        for (index, slice) in response.highlights.enumerated() {
            highlights.append(try makeClip(slice, clipID: quoteIDs[index], framework: quoteFramework))
        }
        return LLMSlices(clips: clips, highlights: highlights)
    }

    private static func makeClip(_ slice: RawSlice, clipID: String, framework: RawFramework) throws -> EDLClip {
        let clip = try EDLClip(
            id: clipID,
            title: slice.title,
            reason: slice.reason,
            score: slice.score,
            tags: slice.tags,
            category: slice.category,
            frameworkId: framework.id,
            frameworkTitle: framework.title,
            mode: slice.mode,
            segments: try slice.segments.map { try segment($0, reason: $0.keepReason) },
            removedSegments: try slice.removedSegments.map { try segment($0, reason: $0.reason) }
        )
        try checkOuterBoundary(slice, against: clip)
        return clip
    }

    /// The LLM's outer `start`/`end` must agree (±0.5s) with its own segments, or the plan is incoherent.
    private static func checkOuterBoundary(_ slice: RawSlice, against clip: EDLClip) throws {
        let start = try Timecode.parse(slice.start)
        let end = try Timecode.parse(slice.end)
        guard end > start else { throw EDLClipError.nonPositiveDuration(clipID: clip.id, start: start, end: end) }
        guard abs(start - clip.startSec) <= 0.5, abs(end - clip.endSec) <= 0.5 else {
            throw EDLClipError.outerBoundaryMismatch(clipID: clip.id)
        }
    }

    private static func segment(_ raw: RawSegment, reason: String?) throws -> EDLSegment {
        EDLSegment(startSec: try Timecode.parse(raw.start), endSec: try Timecode.parse(raw.end), reason: reason)
    }

    struct RawResponse: Decodable {
        let frameworks: [RawFramework]
        let highlights: [RawSlice]
    }

    struct RawFramework: Decodable {
        let id: String
        let title: String
        let slices: [RawSlice]
    }

    struct RawSlice: Decodable {
        let title: String
        let reason: String
        let start: String
        let end: String
        let mode: String
        let score: Double
        let category: String?
        let tags: [String]
        let segments: [RawSegment]
        let removedSegments: [RawSegment]

        enum CodingKeys: String, CodingKey {
            case title, reason, start, end, mode, score, category, tags, segments
            case removedSegments = "removed_segments"
        }
    }

    struct RawSegment: Decodable {
        let start: String
        let end: String
        let keepReason: String?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case start, end, reason
            case keepReason = "keep_reason"
        }
    }
}
