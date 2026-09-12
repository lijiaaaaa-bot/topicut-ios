import Testing
@testable import LiveSliceUI

struct TrimTimelineTests {
    @Test func clampsEachEdgeSoKeptStaysAboveTheFloor() {
        var draft = TrimDraft(duration: 20, originStart: 60, leading: 100, trailing: 100)
        #expect(draft.leading == 19.5)
        #expect(draft.trailing == 0)
        #expect(draft.kept == 0.5)
        draft.moveEnd(fraction: 0)
        #expect(draft.endTime == draft.startTime + 0.5)
        draft.moveStart(fraction: 1)
        #expect(draft.kept == 0.5)
        #expect(draft.startTime >= 60)
        #expect(draft.endTime <= 80)
    }

    @Test func timesIncludeOriginAndDirtyTracksEdits() {
        var draft = TrimDraft(duration: 36, originStart: 72)
        #expect(draft.isDirty == false)
        #expect(draft.startTime == 72)
        #expect(draft.endTime == 108)
        draft.moveStart(fraction: 12 / 36)
        draft.moveEnd(fraction: 30 / 36)
        #expect(draft.isDirty)
        #expect(abs(draft.startTime - 84) < 0.001)
        #expect(abs(draft.endTime - 102) < 0.001)
        #expect(abs(draft.startFraction - 1.0 / 3) < 0.001)
        #expect(abs(draft.endFraction - 30.0 / 36) < 0.001)
    }

    @Test func handleHitMeetsThumbMinimum() {
        #expect(TrimTimeline.handleHit >= 44)
    }

    @Test func zeroDurationDoesNotMove() {
        var draft = TrimDraft(duration: 0, originStart: 10, leading: 4, trailing: 2)
        #expect(draft.leading == 0)
        #expect(draft.trailing == 0)
        #expect(draft.startFraction == 0)
        #expect(draft.endFraction == 1)
        draft.moveStart(fraction: 0.5)
        draft.moveEnd(fraction: 0.9)
        #expect(draft.leading == 0)
        #expect(draft.trailing == 0)
    }
}
