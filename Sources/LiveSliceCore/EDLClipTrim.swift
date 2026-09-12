// Why: App-side trim of an EDL clip's outer edges without calling the LLM. Pure geometry on
// segments so the workbench can preview the shorter cut immediately (ADR-0026).

import Foundation

public enum EDLClipTrimError: Error, Equatable, Sendable {
    case nonPositiveDuration
    case emptyAfterTrim(clipID: String)
}

public enum EDLClipTrim {
    /// Shortens the clip by cutting `leading` seconds from the start and `trailing` from the end
    /// of the kept timeline. Segments are rewritten; removed_segments that fall outside are dropped.
    public static func trimming(_ clip: EDLClip, leading: Double, trailing: Double) throws -> EDLClip {
        guard leading >= 0, trailing >= 0 else { throw EDLClipTrimError.nonPositiveDuration }
        let newStart = clip.startSec + leading
        let newEnd = clip.endSec - trailing
        guard newEnd - newStart > 0.05 else { throw EDLClipTrimError.emptyAfterTrim(clipID: clip.id) }

        var kept: [EDLSegment] = []
        for seg in clip.segments {
            let s = max(seg.startSec, newStart)
            let e = min(seg.endSec, newEnd)
            if e > s {
                kept.append(EDLSegment(startSec: s, endSec: e, reason: seg.reason))
            }
        }
        guard !kept.isEmpty else { throw EDLClipTrimError.emptyAfterTrim(clipID: clip.id) }

        let removed = clip.removedSegments.compactMap { seg -> EDLSegment? in
            let s = max(seg.startSec, newStart)
            let e = min(seg.endSec, newEnd)
            guard e > s else { return nil }
            return EDLSegment(startSec: s, endSec: e, reason: seg.reason)
        }

        let mode = kept.count == 1 ? EDLClip.modeContinuous : EDLClip.modeCompressedConcat
        return try EDLClip(
            id: clip.id, title: clip.title, reason: clip.reason, score: clip.score, tags: clip.tags,
            category: clip.category, frameworkId: clip.frameworkId, frameworkTitle: clip.frameworkTitle,
            mode: mode, segments: kept, removedSegments: removed
        )
    }
}
