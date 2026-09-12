import Testing
@testable import LiveSliceRender

struct LookPresetTests {
    @Test func phoneHighlightUsesPortraitAndWords() {
        #expect(LookPreset.phoneHighlight.framing == .phonePortrait)
        #expect(LookPreset.phoneHighlight.style == .highlightWord)
        #expect(LookPreset.phoneHighlight.requiresWordTimings)
        #expect(!LookPreset.sourceClean.requiresWordTimings)
    }

    @Test func fitCleanLetterboxes() {
        #expect(LookPreset.fitClean.framing == .portraitFit)
        #expect(LookPreset.fitClean.style == .clean)
    }

    @Test func everyPresetHasANote() {
        for preset in LookPreset.allCases {
            #expect(!preset.note.isEmpty)
        }
    }
}
