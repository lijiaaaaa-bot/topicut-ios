import Foundation
import Testing
@testable import LiveSliceASR

struct SpeechLanguageDetectorTests {
    @Test func choosesChineseWhenCJKDominates() throws {
        let locale = try SpeechLanguageDetector.choose(
            zhText: "今天我们来聊一聊人工智能视频切片的三个要点。",
            enText: "Xin Tian woman, Lai Liao yi, Liao, Yengung, Xi, Pian."
        )
        #expect(locale.identifier == "zh_CN")
    }

    @Test func choosesEnglishWhenLatinDominatesAndChineseIsGarbled() throws {
        let locale = try SpeechLanguageDetector.choose(
            zhText: "Today we are goin to tak about artifialelge anideomeding.",
            enText: "Today, we are going to talk about artificial intelligence and video editing."
        )
        #expect(locale.identifier == "en_US")
    }

    @Test func emptyProbeIsNoSpeech() {
        #expect(SpeechLanguageDetector.score(zhText: "", enText: "") == .empty)
        #expect(SpeechLanguageDetector.score(zhText: "...", enText: "!!!") == .empty)
        #expect(throws: SpeechTranscriptionError.noSpeechDetected) {
            try SpeechLanguageDetector.choose(zhText: "", enText: "")
        }
    }

    @Test func cjkAndLatinRatios() {
        #expect(SpeechLanguageDetector.cjkRatio("今天人工智能") == 1)
        #expect(SpeechLanguageDetector.cjkRatio("今天AI") == 0.5)
        #expect(SpeechLanguageDetector.latinRatio("Hello world") == 1)
        #expect(SpeechLanguageDetector.cjkRatio("abc") == 0)
        #expect(SpeechLanguageDetector.latinRatio("") == 0)
    }

    @Test func noSpeechDetectedHasReadableMessage() {
        let message = SpeechTranscriptionError.noSpeechDetected.localizedDescription
        #expect(message.contains("人声"))
    }
}
