// Why: merge two topic/highlight clips into one compressed_concat EDL clip without calling the
// LLM — the user stitches adjacent moments on the workbench and previews immediately (ADR-0026).

import Foundation

public enum EDLClipMergeError: Error, Equatable, Sendable {
    case sameClip
    case emptyAfterMerge
}

public enum EDLClipMerge {
    /// Joins `first` then `second` in source order. Segments are concatenated; gaps between the
    /// clips become part of the kept timeline only if they were already kept — inter-clip gaps
    /// are not invented. Removed segments from both sides that still sit inside the new outer
    /// boundary are kept.
    public static func merging(_ first: EDLClip, _ second: EDLClip) throws -> EDLClip {
        guard first.id != second.id else { throw EDLClipMergeError.sameClip }
        let ordered = first.startSec <= second.startSec ? (first, second) : (second, first)
        let a = ordered.0
        let b = ordered.1
        let segments = (a.segments + b.segments).sorted { $0.startSec < $1.startSec }
        guard !segments.isEmpty else { throw EDLClipMergeError.emptyAfterMerge }
        for i in 1..<segments.count {
            if segments[i].startSec < segments[i - 1].endSec - 0.001 {
                throw EDLClipMergeError.emptyAfterMerge
            }
        }
        let outerStart = segments.first!.startSec
        let outerEnd = segments.last!.endSec
        let removed = (a.removedSegments + b.removedSegments).filter {
            $0.startSec >= outerStart - 0.001 && $0.endSec <= outerEnd + 0.001
        }
        let title = a.title == b.title ? a.title : "\(a.title) · \(b.title)"
        let reason = "合并自两条切片"
        let score = min(1, (a.score + b.score) / 2)
        let tags = Array(Set(a.tags + b.tags)).sorted()
        return try EDLClip(
            id: a.id, title: title, reason: reason, score: score, tags: tags,
            category: a.category ?? b.category, frameworkId: a.frameworkId, frameworkTitle: a.frameworkTitle,
            mode: segments.count == 1 ? EDLClip.modeContinuous : EDLClip.modeCompressedConcat,
            segments: segments, removedSegments: removed
        )
    }
}
