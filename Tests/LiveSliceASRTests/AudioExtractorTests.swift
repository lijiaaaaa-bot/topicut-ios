import AVFoundation
import Testing
@testable import LiveSliceASR
import LiveSliceTestSupport

struct AudioExtractorTests {
    @Test func extractsAudioTrackToM4A() async throws {
        let dir = try SyntheticMedia.scratchDirectory("extract")
        let video = dir.appending(path: "v.mp4"), tone = dir.appending(path: "t.m4a")
        let muxed = dir.appending(path: "av.mp4"), out = dir.appending(path: "out.m4a")
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 160, height: 90), durationSec: 2)
        try SyntheticMedia.makeToneAudio(at: tone, durationSec: 2)
        try await SyntheticMedia.mux(video: video, audio: tone, to: muxed)

        try await AudioExtractor.extractAudio(from: muxed, to: out)
        let file = try AVAudioFile(forReading: out)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(abs(seconds - 2) < 0.2)
    }

    @Test func videoWithoutAudioIsAnError() async throws {
        let dir = try SyntheticMedia.scratchDirectory("noaudio")
        let video = dir.appending(path: "v.mp4"), out = dir.appending(path: "out.m4a")
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 160, height: 90), durationSec: 1)
        await #expect(throws: AudioExtractorError.noAudioTrack(video)) {
            try await AudioExtractor.extractAudio(from: video, to: out)
        }
    }

    @Test func extractsLeadingWindowFromAlreadyExtractedAudio() async throws {
        let dir = try SyntheticMedia.scratchDirectory("window")
        let tone = dir.appending(path: "t.m4a"), full = dir.appending(path: "full.m4a")
        let window = dir.appending(path: "w.m4a")
        try SyntheticMedia.makeToneAudio(at: tone, durationSec: 5)
        try await AudioExtractor.extractAudio(from: tone, to: full)
        try await AudioExtractor.extractAudio(from: full, to: window, startSec: 0, maximumDurationSec: 2)
        let file = try AVAudioFile(forReading: window)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(abs(seconds - 2) < 0.35)
    }
}
