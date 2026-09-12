import CoreGraphics
import Testing
@testable import LiveSliceRender

struct CaptionTuneTests {
    @Test func clampsBandAndScale() {
        let tune = CaptionTune(bandY: 2, fontScale: 0.1, textHex: "abcdef", accentHex: "112233")
        #expect(tune.bandY == 1)
        #expect(tune.fontScale == 0.6)
        #expect(tune.textHex == "ABCDEF")
    }

    @Test func stylePutsBandAtBottomMiddleTop() {
        let size = CGSize(width: 1080, height: 1920)
        let bottom = CaptionTune.from(position: .bottom).style(renderSize: size)
        let top = CaptionTune.from(position: .top).style(renderSize: size)
        let mid = CaptionTune.from(position: .middle).style(renderSize: size)
        #expect(abs(bottom.bottomInset - SubtitleStyle.vertical1080p.bottomInset) < 0.5)
        #expect(abs(top.bottomInset - (1920 - bottom.bandHeight - SubtitleStyle.vertical1080p.bottomInset)) < 0.5)
        #expect(abs(mid.bottomInset - (bottom.bottomInset + top.bottomInset) / 2) < 0.5)
    }

    @Test func fontScaleChangesFontSize() {
        let size = CGSize(width: 1080, height: 1920)
        let base = CaptionTune.standard.style(renderSize: size)
        let big = CaptionTune(bandY: 0.2, fontScale: 1.5, textHex: "FFFFFF", accentHex: "FFD60A").style(renderSize: size)
        #expect(abs(big.fontSize - base.fontSize * 1.5) < 0.5)
    }

    @Test func exportSuffixEmptyForStandard() {
        #expect(CaptionTune.standard.exportSuffix.isEmpty)
        let custom = CaptionTune(bandY: 0.7, fontScale: 1.2, textHex: "00FF00", accentHex: "FF0000")
        #expect(custom.exportSuffix.contains("y70"))
        #expect(custom.exportSuffix.contains("s120"))
        #expect(custom.exportSuffix.contains("t00FF00"))
        #expect(custom.exportSuffix.contains("aFF0000"))
    }

    @Test func invalidHexThrows() {
        #expect(throws: CaptionTuneError.invalidHex("xyz")) {
            try CaptionTune.cgColor(hex: "xyz")
        }
    }

    @Test func fromPositionMatchesBands() {
        #expect(CaptionTune.from(position: .bottom).bandY == 0)
        #expect(CaptionTune.from(position: .middle).bandY == 0.5)
        #expect(CaptionTune.from(position: .top).bandY == 1)
    }
}
