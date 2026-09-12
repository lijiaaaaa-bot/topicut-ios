import Testing
@testable import LiveSliceRender

struct CaptionStyleTests {
    @Test func cleanKeepsThe1_0FileNameAndOtherSuffixesAreDistinct() {
        #expect(CaptionStyle.clean.exportSuffix == "")
        let suffixes = CaptionStyle.allCases.map(\.exportSuffix)
        #expect(Set(suffixes).count == suffixes.count)
        #expect(CaptionStyle.highlightWord.exportSuffix.hasPrefix("-"))
        #expect(CaptionStyle.none.exportSuffix.hasPrefix("-"))
    }

    @Test func onlyNoneSkipsBurningAndRawValuesRoundTrip() throws {
        #expect(CaptionStyle.allCases.filter(\.requiresWordTimings) == [.highlightWord])
        #expect(CaptionStyle.allCases.filter { !$0.burnsCaptions } == [.none])
        for style in CaptionStyle.allCases {
            #expect(CaptionStyle(rawValue: style.rawValue) == style)
        }
        #expect(CaptionStyle(rawValue: "neon") == nil)
    }
}
