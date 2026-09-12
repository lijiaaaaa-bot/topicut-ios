import Testing
@testable import LiveSliceCore

@Suite("EDLClipMerge")
struct EDLClipMergeTests {
    @Test func mergesAdjacentClipsInOrder() throws {
        let a = try EDLClip(
            id: "f_01_c_01", title: "甲", reason: "a", score: 0.8, tags: ["x"], category: nil,
            frameworkId: "f_01", frameworkTitle: "框", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 1, endSec: 5, reason: nil)], removedSegments: []
        )
        let b = try EDLClip(
            id: "f_01_c_02", title: "乙", reason: "b", score: 0.6, tags: ["y"], category: nil,
            frameworkId: "f_01", frameworkTitle: "框", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 8, endSec: 12, reason: nil)], removedSegments: []
        )
        let merged = try EDLClipMerge.merging(a, b)
        #expect(merged.id == a.id)
        #expect(merged.segments.count == 2)
        #expect(merged.startSec == 1 && merged.endSec == 12)
        #expect(merged.mode == EDLClip.modeCompressedConcat)
        #expect(merged.title.contains("甲"))
    }

    @Test func overlappingSegmentsFail() throws {
        let a = try EDLClip(
            id: "a", title: "甲", reason: "a", score: 0.5, tags: [], category: nil,
            frameworkId: "f", frameworkTitle: "f", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 0, endSec: 5, reason: nil)], removedSegments: []
        )
        let b = try EDLClip(
            id: "b", title: "乙", reason: "b", score: 0.5, tags: [], category: nil,
            frameworkId: "f", frameworkTitle: "f", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 4, endSec: 9, reason: nil)], removedSegments: []
        )
        #expect(throws: EDLClipMergeError.emptyAfterMerge) { try EDLClipMerge.merging(a, b) }
    }
}
