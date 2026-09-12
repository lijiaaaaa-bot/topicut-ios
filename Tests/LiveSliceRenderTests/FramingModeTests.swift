import CoreGraphics
import Testing
@testable import LiveSliceRender

@Suite("FramingMode")

struct FramingModeTests {
    @Test func phonePortraitIsAlways1080x1920() {
        #expect(FramingMode.phonePortrait.renderSize(orientedSource: CGSize(width: 3840, height: 2160)) == CGSize(width: 1080, height: 1920))
        #expect(FramingMode.phonePortrait.exportSuffix == "-9x16")
        #expect(FramingMode.sourceAspect.exportSuffix.isEmpty)
        #expect(FramingMode.portraitFit.exportSuffix == "-fit9x16")
        #expect(FramingMode.portraitFit.renderSize(orientedSource: CGSize(width: 1920, height: 1080)) == CGSize(width: 1080, height: 1920))
    }

    @Test func sourceAspectStillCapsAt1920() {
        let size = FramingMode.sourceAspect.renderSize(orientedSource: CGSize(width: 3840, height: 2160))
        #expect(size == CGSize(width: 1920, height: 1080))
    }
}
