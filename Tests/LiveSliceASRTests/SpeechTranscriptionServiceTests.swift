import Foundation
import Testing
@testable import LiveSliceASR
import LiveSliceCore
import LiveSliceTestSupport

/// Real on-device recognition: speech synthesized by `say`, muxed into a video, transcribed by
/// SpeechAnalyzer. Requires the zh_CN model (downloaded on first run) — no stubbed recognizer.
struct SpeechTranscriptionServiceTests {
    static let spoken = "今天我们来聊一聊人工智能视频切片的三个要点。第一是主题完整，第二是节奏紧凑，第三是字幕清晰。"

    @Test func transcribesChineseSpeechFromVideoIntoCues() async throws {
        let dir = try SyntheticMedia.scratchDirectory("asr")
        let speech = dir.appending(path: "speech.m4a"), video = dir.appending(path: "v.mp4"), muxed = dir.appending(path: "av.mp4")
        try SyntheticMedia.makeSpeechAudio(text: Self.spoken, voice: "Tingting", to: speech)
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 320, height: 180), durationSec: 12)
        try await SyntheticMedia.mux(video: video, audio: speech, to: muxed)

        let service = SpeechTranscriptionService(locale: Locale(identifier: "zh-CN"))
        try await service.installAssetsIfNeeded { _ in }
        #expect(try await service.assetState() == .installed)

        let progressBox = ProgressBox()
        let cues = try await service.transcribe(mediaURL: muxed, scratchDirectory: dir) { progressBox.record($0) }
        let joined = cues.map(\.text).joined()
        #expect(cues.count >= 2, "expected sentence-shaped cues, got \(cues)")
        #expect(joined.contains("视频切片") || joined.contains("切片"), "transcript: \(joined)")
        #expect(joined.contains("字幕"), "transcript: \(joined)")
        for (index, cue) in cues.enumerated() {
            #expect(cue.end > cue.start)
            #expect(cue.end <= 12.5)
            if index > 0 { #expect(cue.start >= cues[index - 1].start) }
        }
        #expect(progressBox.last == 1)
        // The cues must serialize to SRT that the slicing side parses back unchanged.
        let srt = try SRTWriter.serialize(cues)
        #expect(try SRTParser.parse(srt) == cues)
    }

    @Test func unsupportedLocaleIsAnError() async {
        let service = SpeechTranscriptionService(locale: Locale(identifier: "tlh-XX"))
        await #expect(throws: SpeechTranscriptionError.localeUnsupported("tlh-XX")) {
            try await service.assetState()
        }
    }

    @Test func supportedLocalesIncludeChineseAndEnglish() async {
        let ids = await SpeechTranscriptionService.supportedLocaleIdentifiers()
        #expect(ids.contains("zh_CN"))
        #expect(ids.contains("en_US"))
    }

    @Test func automaticDetectionPicksEnglishForEnglishSpeech() async throws {
        let dir = try SyntheticMedia.scratchDirectory("asr-auto-en")
        let speech = dir.appending(path: "speech.m4a")
        let video = dir.appending(path: "v.mp4")
        let muxed = dir.appending(path: "av.mp4")
        let spoken = "Today we are going to talk about artificial intelligence and video editing."
        try SyntheticMedia.makeSpeechAudio(text: spoken, voice: "Samantha", to: speech)
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 320, height: 180), durationSec: 6)
        try await SyntheticMedia.mux(video: video, audio: speech, to: muxed)

        try await SpeechTranscriptionService.installAssets(for: .automatic) { _ in }
        let outcome = try await SpeechTranscriptionService.transcribe(
            mediaURL: muxed, preference: .automatic, scratchDirectory: dir
        ) { _ in }
        #expect(outcome.locale.identifier.hasPrefix("en"))
        let joined = outcome.cues.map(\.text).joined(separator: " ")
        #expect(joined.contains("artificial") || joined.contains("intelligence"), "transcript: \(joined)")
        #expect(!joined.contains("artifialelge"))
    }

    @Test func automaticDetectionPicksChineseForChineseSpeech() async throws {
        let dir = try SyntheticMedia.scratchDirectory("asr-auto-zh")
        let speech = dir.appending(path: "speech.m4a")
        let video = dir.appending(path: "v.mp4")
        let muxed = dir.appending(path: "av.mp4")
        try SyntheticMedia.makeSpeechAudio(text: Self.spoken, voice: "Tingting", to: speech)
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 320, height: 180), durationSec: 12)
        try await SyntheticMedia.mux(video: video, audio: speech, to: muxed)

        try await SpeechTranscriptionService.installAssets(for: .automatic) { _ in }
        let outcome = try await SpeechTranscriptionService.transcribe(
            mediaURL: muxed, preference: .automatic, scratchDirectory: dir
        ) { _ in }
        #expect(outcome.locale.identifier.hasPrefix("zh"))
        let joined = outcome.cues.map(\.text).joined()
        #expect(joined.contains("切片") || joined.contains("视频"), "transcript: \(joined)")
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func record(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
}
