import CoreGraphics
import Testing
import LiveSliceCore
@testable import LiveSliceRender

struct CaptionPositionTests {
    @Test func bottomKeepsTheDefaultInsetAndOtherPlacesMoveTheBand() {
        let size = CGSize(width: 1080, height: 1920)
        let bottom = CaptionPosition.bottom.style(renderSize: size)
        let middle = CaptionPosition.middle.style(renderSize: size)
        let top = CaptionPosition.top.style(renderSize: size)
        #expect(bottom.bottomInset == SubtitleStyle.vertical1080p.bottomInset)
        #expect(abs(middle.bottomInset - (1920 - bottom.bandHeight) / 2) < 0.5)
        #expect(abs(top.bottomInset - (1920 - bottom.bandHeight - bottom.bottomInset)) < 0.5)
        #expect(top.bottomInset > middle.bottomInset)
        #expect(middle.bottomInset > bottom.bottomInset)
    }

    @Test func exportSuffixIsEmptyOnlyForBottom() {
        #expect(CaptionPosition.bottom.exportSuffix.isEmpty)
        #expect(CaptionPosition.middle.exportSuffix == "-mid")
        #expect(CaptionPosition.top.exportSuffix == "-top")
    }
}

