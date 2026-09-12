import Testing
@testable import LiveSliceCore

@Suite("SlicingTaste")
struct SlicingTasteTests {
    @Test func fewerShrinksClipCounts() {
        let base = ClipCountPolicy(durationMinutes: 30, minClips: 5, maxClips: 10, hardMaxClips: 12)
        let scaled = SlicingTaste(topicDensity: .fewer).apply(base)
        #expect(scaled.minClips == 3)
        #expect(scaled.maxClips == 6)
        #expect(scaled.hardMaxClips == 7)
    }

    @Test func moreGrowsClipCounts() {
        let base = ClipCountPolicy(durationMinutes: 10, minClips: 1, maxClips: 3, hardMaxClips: 4)
        let scaled = SlicingTaste(topicDensity: .more).apply(base)
        #expect(scaled.minClips == 1)
        #expect(scaled.maxClips == 4)
        #expect(scaled.hardMaxClips == 6)
    }

    @Test func punchyShortensHighlightBand() {
        let base = HighlightCountPolicy(durationMinutes: 30, minHighlights: 4, maxHighlights: 8)
        let scaled = SlicingTaste(highlightSpan: .punchy).apply(base)
        #expect(scaled.minSeconds == 12)
        #expect(scaled.maxSeconds == 45)
        #expect(scaled.minHighlights == 4)
    }

    @Test func keyFragmentChangesWithTaste() {
        #expect(SlicingTaste.standard.keyFragment == "standard+standard")
        #expect(SlicingTaste(topicDensity: .more, highlightSpan: .roomy).keyFragment == "more+roomy")
    }
}
