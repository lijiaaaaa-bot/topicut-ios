// Why: in-app trim / discard / merge rewrite the same EDL a renderer already executes.
// Mutations throw on an empty or out-of-range result so a bad drag cannot persist a clip
// that encode/decode would reject. ASR and DeepSeek are not invoked here.

import Foundation

public enum EDLEditError: Error, Equatable, Sendable, LocalizedError {
    case clipNotFound(String)
    case noCurrentClip
    case noNextClip
    case emptyAfterTrim(clipID: String)
    case rangeOutsideSource(clipID: String, start: Double, end: Double)
    case nonPositiveTrim(clipID: String, start: Double, end: Double)

    public var errorDescription: String? {
        switch self {
        case .clipNotFound(let id): "找不到切片 \(id)"
        case .noCurrentClip: "没有可编辑的切片"
        case .noNextClip: "没有下一条可合并"
        case .emptyAfterTrim: "修剪后没有保留片段"
        case .rangeOutsideSource: "修剪超出源范围"
        case .nonPositiveTrim: "起点必须早于终点"
        }
    }
}

/// Pure EDL rewrites used by `EDLEditor`. Each operation returns a validated clip or document.
public enum EDLEdit {
    public static func trim(
        _ clip: EDLClip, start: Double, end: Double, sourceStart: Double, sourceEnd: Double
    ) throws -> EDLClip {
        guard end > start else {
            throw EDLEditError.nonPositiveTrim(clipID: clip.id, start: start, end: end)
        }
        guard start >= sourceStart - 0.001, end <= sourceEnd + 0.001 else {
            throw EDLEditError.rangeOutsideSource(clipID: clip.id, start: start, end: end)
        }
        let kept = clippedKept(clip, start: start, end: end)
        guard let first = kept.first, let last = kept.last else {
            throw EDLEditError.emptyAfterTrim(clipID: clip.id)
        }
        let removed = intersect(clip.removedSegments, start: first.startSec, end: last.endSec)
        return try rebuild(clip, segments: kept, removed: removed)
    }

    public static func merge(_ leading: EDLClip, with trailing: EDLClip) throws -> EDLClip {
        let kept = coalesce(leading.segments + trailing.segments)
        guard let first = kept.first, let last = kept.last else {
            throw EDLEditError.emptyAfterTrim(clipID: leading.id)
        }
        var removed = leading.removedSegments + trailing.removedSegments
        if let gap = gapBetween(leading, trailing) { removed.append(gap) }
        removed = subtractKept(from: intersect(removed, start: first.startSec, end: last.endSec), kept: kept)
        return try EDLClip(
            id: leading.id, title: leading.title, reason: leading.reason, score: leading.score,
            tags: uniqueTags(leading.tags + trailing.tags), category: leading.category,
            frameworkId: leading.frameworkId, frameworkTitle: leading.frameworkTitle,
            mode: kept.count == 1 ? EDLClip.modeContinuous : EDLClip.modeCompressedConcat,
            segments: kept, removedSegments: coalesce(removed)
        )
    }

    public static func discarding(_ document: EDLDocument, clipID: String) throws -> (EDLDocument, String?) {
        guard let index = document.clips.firstIndex(where: { $0.id == clipID }) else {
            throw EDLEditError.clipNotFound(clipID)
        }
        var clips = document.clips
        clips.remove(at: index)
        let nextID: String?
        if clips.isEmpty { nextID = nil }
        else if index < clips.count { nextID = clips[index].id }
        else { nextID = clips[index - 1].id }
        return (document.replacingClips(clips), nextID)
    }

    /// Filmstrip bounds around a clip, padded so in/out handles are not stuck on the edges.
    public static func window(
        clipStart: Double, clipEnd: Double, sourceStart: Double, sourceEnd: Double
    ) -> TrimWindow {
        TrimWindow(clipStart: clipStart, clipEnd: clipEnd, sourceStart: sourceStart, sourceEnd: sourceEnd)
    }
}

/// Visible time span of the trim filmstrip. Positions map linearly onto source seconds.
public struct TrimWindow: Equatable, Sendable {
    public let startSec: Double
    public let endSec: Double

    public var span: Double { max(0.001, endSec - startSec) }

    public init(clipStart: Double, clipEnd: Double, sourceStart: Double, sourceEnd: Double) {
        let duration = max(0, clipEnd - clipStart)
        let pad = max(duration * 0.35, 15)
        let rawStart = min(max(clipStart - pad, sourceStart), sourceEnd)
        let rawEnd = max(min(clipEnd + pad, sourceEnd), rawStart + 0.001)
        startSec = rawStart
        endSec = rawEnd
    }

    public func position(of time: Double, width: Double) -> Double {
        width * (time - startSec) / span
    }

    public func time(at position: Double, width: Double) -> Double {
        guard width > 0 else { return startSec }
        let mapped = startSec + span * (position / width)
        return min(max(mapped, startSec), endSec)
    }

    public func ticks(count: Int) -> [Double] {
        guard count > 1 else { return [startSec] }
        return (0..<count).map { startSec + span * Double($0) / Double(count - 1) }
    }
}

extension EDLEdit {
    static func clippedKept(_ clip: EDLClip, start: Double, end: Double) -> [EDLSegment] {
        var kept = clip.segments
        if start < clip.startSec - 0.001, let first = kept.first {
            kept[0] = EDLSegment(startSec: start, endSec: first.endSec, reason: first.reason)
        }
        if end > clip.endSec + 0.001, let last = kept.last {
            kept[kept.count - 1] = EDLSegment(startSec: last.startSec, endSec: end, reason: last.reason)
        }
        return intersect(kept, start: start, end: end)
    }

    static func rebuild(_ clip: EDLClip, segments: [EDLSegment], removed: [EDLSegment]) throws -> EDLClip {
        try EDLClip(
            id: clip.id, title: clip.title, reason: clip.reason, score: clip.score, tags: clip.tags,
            category: clip.category, frameworkId: clip.frameworkId, frameworkTitle: clip.frameworkTitle,
            mode: segments.count == 1 ? EDLClip.modeContinuous : EDLClip.modeCompressedConcat,
            segments: segments, removedSegments: removed
        )
    }

    static func intersect(_ segments: [EDLSegment], start: Double, end: Double) -> [EDLSegment] {
        segments.compactMap { segment in
            let lo = max(segment.startSec, start)
            let hi = min(segment.endSec, end)
            guard hi > lo + 0.0005 else { return nil }
            return EDLSegment(startSec: lo, endSec: hi, reason: segment.reason)
        }
    }

    static func coalesce(_ segments: [EDLSegment]) -> [EDLSegment] {
        let ordered = segments.sorted { $0.startSec < $1.startSec }
        var result: [EDLSegment] = []
        for segment in ordered {
            guard let last = result.last, segment.startSec <= last.endSec + 0.001 else {
                result.append(segment)
                continue
            }
            result[result.count - 1] = EDLSegment(
                startSec: last.startSec, endSec: max(last.endSec, segment.endSec), reason: last.reason
            )
        }
        return result
    }

    static func gapBetween(_ leading: EDLClip, _ trailing: EDLClip) -> EDLSegment? {
        if leading.endSec < trailing.startSec - 0.001 {
            return EDLSegment(startSec: leading.endSec, endSec: trailing.startSec, reason: nil)
        }
        if trailing.endSec < leading.startSec - 0.001 {
            return EDLSegment(startSec: trailing.endSec, endSec: leading.startSec, reason: nil)
        }
        return nil
    }

    static func subtractKept(from removed: [EDLSegment], kept: [EDLSegment]) -> [EDLSegment] {
        var leftovers = removed
        for keep in kept {
            leftovers = leftovers.flatMap { subtract($0, keep) }
        }
        return leftovers
    }

    static func subtract(_ piece: EDLSegment, _ keep: EDLSegment) -> [EDLSegment] {
        if piece.endSec <= keep.startSec + 0.001 || piece.startSec >= keep.endSec - 0.001 {
            return [piece]
        }
        var parts: [EDLSegment] = []
        if piece.startSec < keep.startSec - 0.001 {
            parts.append(EDLSegment(startSec: piece.startSec, endSec: min(piece.endSec, keep.startSec), reason: piece.reason))
        }
        if piece.endSec > keep.endSec + 0.001 {
            parts.append(EDLSegment(startSec: max(piece.startSec, keep.endSec), endSec: piece.endSec, reason: piece.reason))
        }
        return parts
    }

    static func uniqueTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.filter { seen.insert($0).inserted }
    }
}
