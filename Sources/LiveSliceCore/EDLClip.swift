// Why: one clip of the Edit Decision List. The EDL is the contract between "decide what to cut"
// (this package) and "actually cut it" (a future on-device renderer); validation lives next to the
// data so no producer can emit a clip a renderer cannot execute.

import Foundation

/// A kept or removed time range. `reason` is `keep_reason` for kept segments and `reason` for removed ones.
public struct EDLSegment: Codable, Equatable, Sendable {
    public let start: String
    public let end: String
    public let startSec: Double
    public let endSec: Double
    public let reason: String?

    public init(startSec: Double, endSec: Double, reason: String?) {
        self.startSec = (startSec * 1000).rounded() / 1000
        self.endSec = (endSec * 1000).rounded() / 1000
        self.start = Timecode.format(startSec)
        self.end = Timecode.format(endSec)
        self.reason = reason
    }
}

public enum EDLClipError: Error, Equatable, Sendable {
    case emptySegments(clipID: String)
    case nonPositiveDuration(clipID: String, start: Double, end: Double)
    case overlappingSegments(clipID: String, index: Int)
    case scoreOutOfRange(clipID: String, score: Double)
    case emptyTitle(clipID: String)
    case invalidMode(clipID: String, mode: String)
    /// `start`/`end` on the clip do not equal the first segment start / last segment end.
    case outerBoundaryMismatch(clipID: String)
    /// A removed range lies (partly) outside the clip's outer boundary.
    case removedSegmentOutsideClip(clipID: String, removedIndex: Int)
    /// A removed range overlaps a kept segment — a renderer could not honour both.
    case removedOverlapsKept(clipID: String, removedIndex: Int, segmentIndex: Int)
}

public struct EDLClip: Codable, Equatable, Sendable {
    public static let modeContinuous = "continuous"
    public static let modeCompressedConcat = "compressed_concat"
    private static let allowedModes: Set<String> = [modeContinuous, modeCompressedConcat]

    public let id: String
    public let title: String
    public let reason: String
    public let start: String
    public let end: String
    public let startSec: Double
    public let endSec: Double
    public let score: Double
    public let tags: [String]
    public let category: String?
    public let frameworkId: String
    public let frameworkTitle: String
    public let mode: String
    public let segments: [EDLSegment]
    public let removedSegments: [EDLSegment]

    /// Builds a clip whose outer boundary is derived from its segments, validating every invariant.
    public init(
        id: String, title: String, reason: String, score: Double, tags: [String], category: String?,
        frameworkId: String, frameworkTitle: String, mode: String,
        segments: [EDLSegment], removedSegments: [EDLSegment]
    ) throws {
        guard let first = segments.first, let last = segments.last else {
            throw EDLClipError.emptySegments(clipID: id)
        }
        self.id = id
        self.title = title
        self.reason = reason
        self.score = score
        self.tags = tags
        self.category = category
        self.frameworkId = frameworkId
        self.frameworkTitle = frameworkTitle
        self.mode = mode
        self.segments = segments
        self.removedSegments = removedSegments
        self.startSec = first.startSec
        self.endSec = last.endSec
        self.start = first.start
        self.end = last.end
        try validateInvariants()
    }

    /// Checks every invariant a renderer relies on. Also run after decoding, because `Codable`
    /// synthesis bypasses the throwing initializer.
    public func validateInvariants() throws {
        guard let first = segments.first, let last = segments.last else {
            throw EDLClipError.emptySegments(clipID: id)
        }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw EDLClipError.emptyTitle(clipID: id) }
        guard (0.0...1.0).contains(score) else { throw EDLClipError.scoreOutOfRange(clipID: id, score: score) }
        guard Self.allowedModes.contains(mode) else { throw EDLClipError.invalidMode(clipID: id, mode: mode) }
        try Self.validate(segments: segments, clipID: id)
        try Self.validate(segments: removedSegments, clipID: id)
        guard startSec == first.startSec, endSec == last.endSec, start == first.start, end == last.end else {
            throw EDLClipError.outerBoundaryMismatch(clipID: id)
        }
        try validateRemovedAgainstKept()
    }

    /// Removed ranges must sit inside the clip and never intersect a kept segment (touching is fine).
    private func validateRemovedAgainstKept() throws {
        let tolerance = 0.001
        for (removedIndex, removed) in removedSegments.enumerated() {
            guard removed.startSec >= startSec - tolerance, removed.endSec <= endSec + tolerance else {
                throw EDLClipError.removedSegmentOutsideClip(clipID: id, removedIndex: removedIndex)
            }
            for (segmentIndex, kept) in segments.enumerated()
            where removed.startSec < kept.endSec - tolerance && removed.endSec > kept.startSec + tolerance {
                throw EDLClipError.removedOverlapsKept(clipID: id, removedIndex: removedIndex, segmentIndex: segmentIndex)
            }
        }
    }

    /// Every range must have `end > start`; ranges must be ordered and non-overlapping.
    public static func validate(segments: [EDLSegment], clipID: String) throws {
        var previousEnd: Double?
        for (index, segment) in segments.enumerated() {
            guard segment.endSec > segment.startSec else {
                throw EDLClipError.nonPositiveDuration(clipID: clipID, start: segment.startSec, end: segment.endSec)
            }
            if let previousEnd, segment.startSec < previousEnd - 0.001 {
                throw EDLClipError.overlappingSegments(clipID: clipID, index: index)
            }
            previousEnd = segment.endSec
        }
    }

    /// Total kept duration in seconds.
    public var keptDurationSec: Double {
        segments.reduce(0) { $0 + ($1.endSec - $1.startSec) }
    }

    /// Clip ids for a run of framework ids: `<framework_id>_c_<NN>`, NN counting every clip that
    /// shares the framework id in order. The model may emit one framework id in two blocks;
    /// restarting NN per block gave duplicate ids, and lists keyed by id cannot select duplicates.
    public static func uniqueIDs(frameworkIDs: [String]) -> [String] {
        var ordinalByFramework: [String: Int] = [:]
        return frameworkIDs.map { frameworkID in
            let ordinal = ordinalByFramework[frameworkID, default: 0] + 1
            ordinalByFramework[frameworkID] = ordinal
            return "\(frameworkID)_c_\(String(format: "%02d", ordinal))"
        }
    }

    /// The same clip under another id; everything else, including validation, is unchanged.
    public func withID(_ newID: String) throws -> EDLClip {
        try EDLClip(
            id: newID, title: title, reason: reason, score: score, tags: tags, category: category,
            frameworkId: frameworkId, frameworkTitle: frameworkTitle, mode: mode,
            segments: segments, removedSegments: removedSegments
        )
    }
}
