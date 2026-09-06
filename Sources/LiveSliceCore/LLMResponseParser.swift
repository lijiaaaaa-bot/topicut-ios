// Why: LLM output is untrusted text. This is the one place that turns it into validated EDL
// clips; every field the prompt demands is required here, and a bad range is an error rather
// than a silently dropped item (the Python original skipped `start == end` placeholders).

import Foundation

public enum LLMResponseError: Error, Equatable, Sendable {
    /// No `{ ... }` object could be located in the text.
    case noJSONObject(preview: String)
    /// JSON was found but does not match the expected `frameworks[].slices[]` shape.
    case decoding(String)
    /// Frameworks array was present but empty — the LLM produced no slices.
    case noSlices
}

public enum LLMResponseParser {
    /// Parses the raw chat response into validated clips.
    public static func parseClips(from text: String) throws -> [EDLClip] {
        let json = try extractJSONObject(from: text)
        let response: RawResponse
        do {
            response = try JSONDecoder().decode(RawResponse.self, from: Data(json.utf8))
        } catch let error as DecodingError {
            throw LLMResponseError.decoding(describe(error))
        }
        var clips: [EDLClip] = []
        for framework in response.frameworks {
            for (offset, slice) in framework.slices.enumerated() {
                let clipID = "\(framework.id)_c_\(String(format: "%02d", offset + 1))"
                clips.append(try makeClip(slice, clipID: clipID, framework: framework))
            }
        }
        guard !clips.isEmpty else { throw LLMResponseError.noSlices }
        return clips
    }

    /// Strips optional markdown fences and returns the outermost `{...}` substring.
    public static func extractJSONObject(from text: String) throws -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .dropFirst().joined(separator: "\n")
            if let fenceEnd = body.range(of: "```", options: .backwards) {
                body = String(body[..<fenceEnd.lowerBound])
            }
        }
        guard let open = body.firstIndex(of: "{"), let close = body.lastIndex(of: "}"), open < close else {
            throw LLMResponseError.noJSONObject(preview: String(text.prefix(200)))
        }
        return String(body[open...close])
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

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "missing field '\(key.stringValue)' at \(path(context))"
        case let .typeMismatch(type, context):
            return "type mismatch (expected \(type)) at \(path(context))"
        case let .valueNotFound(type, context):
            return "null where \(type) expected at \(path(context))"
        case let .dataCorrupted(context):
            return "corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "<root>" : joined
    }

    struct RawResponse: Decodable {
        let frameworks: [RawFramework]
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
