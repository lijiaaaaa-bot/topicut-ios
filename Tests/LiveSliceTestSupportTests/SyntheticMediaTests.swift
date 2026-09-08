import AVFoundation
import Testing
@testable import LiveSliceTestSupport

struct SyntheticMediaTests {
    @Test func videoHasRequestedSizeAndDuration() async throws {
        let dir = try SyntheticMedia.scratchDirectory("synth")
        let url = dir.appending(path: "v.mp4")
        try await SyntheticMedia.makeVideo(at: url, size: CGSize(width: 320, height: 180), durationSec: 2, color: SyntheticMedia.RGB(red: 0.9, green: 0.1, blue: 0.1))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
    }

    @Test func toneAudioMuxesIntoVideo() async throws {
        let dir = try SyntheticMedia.scratchDirectory("mux")
        let video = dir.appending(path: "v.mp4"), audio = dir.appending(path: "a.m4a"), out = dir.appending(path: "av.mp4")
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 160, height: 90), durationSec: 1.5)
        try SyntheticMedia.makeToneAudio(at: audio, durationSec: 1.5)
        try await SyntheticMedia.mux(video: video, audio: audio, to: out)
        let asset = AVURLAsset(url: out)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    }

    @Test func unwritableOutputIsATypedError() throws {
        let dir = try SyntheticMedia.scratchDirectory("say-bad")
        let missing = dir.appending(path: "no-such-dir/bad.m4a")
        #expect(throws: SyntheticMediaError.self) {
            try SyntheticMedia.makeSpeechAudio(text: "x", voice: "Samantha", to: missing)
        }
    }

    @Test func speechAudioIsProduced() throws {
        let dir = try SyntheticMedia.scratchDirectory("say")
        let url = dir.appending(path: "s.m4a")
        try SyntheticMedia.makeSpeechAudio(text: "hello world", voice: "Samantha", to: url)
        let file = try AVAudioFile(forReading: url)
        #expect(file.length > 0)
    }
}
