import Testing
@testable import LiveSliceCore

struct EDLClipTests {
    @Test func outerBoundaryDerivesFromSegments() throws {
        let clip = try TestSupport.clip()
        #expect(clip.startSec == 1)
        #expect(clip.endSec == 22)
        #expect(clip.start == "00:00:01.000")
        #expect(clip.end == "00:00:22.000")
        #expect(clip.keptDurationSec == 18)
    }

    @Test func rejectsEmptySegments() {
        #expect(throws: EDLClipError.emptySegments(clipID: "x")) { try TestSupport.clip(id: "x", segments: []) }
    }

    @Test func rejectsEndNotAfterStart() {
        #expect(throws: EDLClipError.nonPositiveDuration(clipID: "x", start: 5, end: 5)) {
            try TestSupport.clip(id: "x", segments: [TestSupport.segment(5, 5)])
        }
        #expect(throws: EDLClipError.nonPositiveDuration(clipID: "x", start: 9, end: 8)) {
            try TestSupport.clip(id: "x", removed: [TestSupport.segment(9, 8)])
        }
    }

    @Test func rejectsOverlappingSegments() {
        #expect(throws: EDLClipError.overlappingSegments(clipID: "x", index: 1)) {
            try TestSupport.clip(id: "x", segments: [TestSupport.segment(1, 10), TestSupport.segment(9, 12)])
        }
    }

    @Test func rejectsBadScoreModeAndTitle() {
        #expect(throws: EDLClipError.scoreOutOfRange(clipID: "x", score: 1.2)) { try TestSupport.clip(id: "x", score: 1.2) }
        #expect(throws: EDLClipError.invalidMode(clipID: "x", mode: "loop")) { try TestSupport.clip(id: "x", mode: "loop") }
        #expect(throws: EDLClipError.emptyTitle(clipID: "x")) { try TestSupport.clip(id: "x", title: "  ") }
    }

    @Test func removedInsideGapAndTouchingBoundariesIsValid() throws {
        // Gap exactly between the kept segments, touching both ends: allowed.
        let clip = try TestSupport.clip(removed: [TestSupport.segment(13, 16)])
        #expect(clip.removedSegments.count == 1)
        // Removed range touching the clip start/end but inside the outer boundary (single kept segment case).
        let edge = try TestSupport.clip(
            segments: [TestSupport.segment(1, 10), TestSupport.segment(12, 22)],
            removed: [TestSupport.segment(10, 12)]
        )
        #expect(edge.startSec == 1 && edge.endSec == 22)
        // No removed segments at all is fine.
        #expect(try TestSupport.clip(removed: []).removedSegments.isEmpty)
    }

    @Test func rejectsRemovedBeforeClipStart() {
        #expect(throws: EDLClipError.removedSegmentOutsideClip(clipID: "x", removedIndex: 0)) {
            try TestSupport.clip(id: "x", removed: [TestSupport.segment(0, 0.5)])
        }
    }

    @Test func rejectsRemovedAfterClipEnd() {
        // Mirrors the live DeepSeek output that motivated this invariant: a trailing quiz recorded past `end`.
        #expect(throws: EDLClipError.removedSegmentOutsideClip(clipID: "x", removedIndex: 1)) {
            try TestSupport.clip(id: "x", removed: [TestSupport.segment(13, 16), TestSupport.segment(22, 37.6)])
        }
    }

    @Test func rejectsRemovedOverlappingKept() {
        #expect(throws: EDLClipError.removedOverlapsKept(clipID: "x", removedIndex: 0, segmentIndex: 0)) {
            try TestSupport.clip(id: "x", removed: [TestSupport.segment(12, 16)])
        }
        #expect(throws: EDLClipError.removedOverlapsKept(clipID: "x", removedIndex: 0, segmentIndex: 1)) {
            try TestSupport.clip(id: "x", removed: [TestSupport.segment(13, 17)])
        }
    }

    @Test func rejectsUnorderedKeptSegments() {
        #expect(throws: EDLClipError.overlappingSegments(clipID: "x", index: 1)) {
            try TestSupport.clip(id: "x", segments: [TestSupport.segment(16, 22), TestSupport.segment(1, 13)], removed: [])
        }
    }

    @Test func segmentRoundsToMilliseconds() {
        let segment = EDLSegment(startSec: 1.23456, endSec: 2.0004, reason: nil)
        #expect(segment.startSec == 1.235)
        #expect(segment.endSec == 2.0)
        #expect(segment.start == "00:00:01.235")
    }
}
