import Testing
@testable import LiveSliceCore

@Suite("EDLClipTrim")
struct EDLClipTrimTests {
    @Test func trimsOuterEdgesAndKeepsInnerSegment() throws {
        let clip = try SessionFixturesCore.clip()
        let trimmed = try EDLClipTrim.trimming(clip, leading: 2, trailing: 1)
        #expect(trimmed.startSec == 3)
        #expect(trimmed.endSec == 21)
        #expect(trimmed.segments.first?.startSec == 3)
        #expect(trimmed.segments.last?.endSec == 21)
    }

    @Test func emptyAfterTrimThrows() throws {
        let clip = try SessionFixturesCore.clip()
        #expect(throws: EDLClipTrimError.emptyAfterTrim(clipID: clip.id)) {
            try EDLClipTrim.trimming(clip, leading: 20, trailing: 20)
        }
    }
}

/// Minimal clip fixture local to this suite (Core tests must not import UI SessionFixtures).
enum SessionFixturesCore {
    static func clip() throws -> EDLClip {
        try EDLClip(
            id: "f_01_c_01", title: "测试话题", reason: "完整", score: 0.8, tags: [], category: "观点论述",
            frameworkId: "f_01", frameworkTitle: "框架", mode: EDLClip.modeCompressedConcat,
            segments: [
                EDLSegment(startSec: 1, endSec: 13, reason: nil),
                EDLSegment(startSec: 16, endSec: 22, reason: nil),
            ],
            removedSegments: [EDLSegment(startSec: 13, endSec: 16, reason: "答题")]
        )
    }
}
