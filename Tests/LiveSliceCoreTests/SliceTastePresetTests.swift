import Foundation
import Testing
import LiveSliceCore

struct SliceTastePresetTests {
    @Test func everyPresetBuildsATasteAndMatchesItself() {
        for preset in SliceTastePreset.allCases {
            #expect(SliceTastePreset.matching(preset.taste) == preset)
            #expect(!preset.title.isEmpty)
            #expect(!preset.note.isEmpty)
        }
    }

    @Test func freeKnobComboOutsidePresetsMatchesNone() {
        let custom = SlicingTaste(topicDensity: .more, highlightSpan: .punchy)
        #expect(SliceTastePreset.matching(custom) == nil)
    }

    @Test func balancedIsStandardTaste() {
        #expect(SliceTastePreset.balanced.taste == .standard)
    }
}
