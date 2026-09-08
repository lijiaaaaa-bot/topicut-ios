import AVFoundation
import CoreGraphics
import Testing
@testable import LiveSliceRender
import LiveSliceCore
import LiveSliceTestSupport

/// Real AVFoundation export of a synthetic 640×360 source: checks duration, 9:16 size, audio, and
/// that the burnt-in subtitle actually changes pixels in the caption band only while it is shown.
struct ClipRendererTests {
    static func makeSource(dir: URL, seconds: Double) async throws -> URL {
        let video = dir.appending(path: "src.mp4"), tone = dir.appending(path: "tone.m4a"), muxed = dir.appending(path: "src-av.mp4")
        try await SyntheticMedia.makeVideo(at: video, size: CGSize(width: 640, height: 360), durationSec: seconds)
        try SyntheticMedia.makeToneAudio(at: tone, durationSec: seconds)
        try await SyntheticMedia.mux(video: video, audio: tone, to: muxed)
        return muxed
    }

    static func clip() throws -> EDLClip {
        try EDLClip(
            id: "f_01_c_01", title: "测试", reason: "r", score: 0.9, tags: [], category: nil, frameworkId: "f_01", frameworkTitle: "F",
            mode: EDLClip.modeCompressedConcat,
            segments: [EDLSegment(startSec: 1, endSec: 3, reason: nil), EDLSegment(startSec: 5, endSec: 7, reason: nil)],
            removedSegments: [EDLSegment(startSec: 3, endSec: 5, reason: "gap")]
        )
    }

    @Test func rendersSourceShapeWithAudioAndBurntSubtitle() async throws {
        let dir = try SyntheticMedia.scratchDirectory("render")
        let source = try await Self.makeSource(dir: dir, seconds: 8)
        let output = dir.appending(path: "clip.mp4")
        let cues = [SRTCue(index: 1, start: 1.5, end: 2.5, text: "字幕烧录测试字幕烧录测试")]

        let result: RenderResult = try await ClipRenderer().render(sourceURL: source, clip: try Self.clip(), cues: cues, outputURL: output) { _ in }
        #expect(result.durationSec == 4)
        #expect(result.subtitleCount == 1)
        #expect(result.renderSize == CGSize(width: 640, height: 360))

        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 4) < 0.15)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await videoTrack.load(.naturalSize) == CGSize(width: 640, height: 360))
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)

        // Composition time 1.0 s is inside the cue (0.5…1.5); 3.0 s is not.
        let band = Self.captionBand(renderHeight: 360, style: SubtitleStyle.vertical1080p.scaled(to: CGSize(width: 640, height: 360)))
        let withText = try await FramePixels.capture(asset: asset, atSeconds: 1.0)
        let withoutText = try await FramePixels.capture(asset: asset, atSeconds: 3.0)
        #expect(withText.isBluish(x: 320, y: 40), "video content must fill the frame")
        #expect(withText.isBluish(x: 4, y: 180), "source shape: nothing cropped at the left edge")
        #expect(withText.brightPixelCount(inBandFromY: band.top, toY: band.bottom) > 0, "subtitle band must contain text pixels")
        #expect(withoutText.brightPixelCount(inBandFromY: band.top, toY: band.bottom) == 0, "no subtitle outside its window")
    }

    @Test func rendersWithoutSubtitlesWhenDisabled() async throws {
        let dir = try SyntheticMedia.scratchDirectory("render-plain")
        let source = try await Self.makeSource(dir: dir, seconds: 8)
        let output = dir.appending(path: "plain.mp4")
        let options = RenderOptions(frameRate: 30, burnSubtitles: false, subtitleStyle: .vertical1080p)
        let cues = [SRTCue(index: 1, start: 1.5, end: 2.5, text: "不应出现")]
        let result = try await ClipRenderer(options: options).render(sourceURL: source, clip: try Self.clip(), cues: cues, outputURL: output) { _ in }
        #expect(result.subtitleCount == 0)
        let band = Self.captionBand(renderHeight: 360, style: SubtitleStyle.vertical1080p.scaled(to: CGSize(width: 640, height: 360)))
        let frame = try await FramePixels.capture(asset: AVURLAsset(url: output), atSeconds: 1.0)
        #expect(frame.brightPixelCount(inBandFromY: band.top, toY: band.bottom) == 0)
    }

    /// Source aspect must keep the shape *and* still burn scaled captions, not silently drop them.
    @Test func sourceAspectPreservesLandscapeShapeAndBurnsScaledSubtitle() async throws {
        let dir = try SyntheticMedia.scratchDirectory("render-source-aspect")
        let source = try await Self.makeSource(dir: dir, seconds: 8)
        let output = dir.appending(path: "source-aspect.mp4")
        let cues = [SRTCue(index: 1, start: 1.5, end: 2.5, text: "原画比例字幕")]
        let result = try await ClipRenderer(options: .standard).render(
            sourceURL: source, clip: try Self.clip(), cues: cues, outputURL: output
        ) { _ in }
        #expect(result.renderSize == CGSize(width: 640, height: 360))
        #expect(result.subtitleCount == 1)

        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 640, height: 360))

        let style = SubtitleStyle.vertical1080p.scaled(to: CGSize(width: 640, height: 360))
        let band = Self.captionBand(renderHeight: 360, style: style)
        let withText = try await FramePixels.capture(asset: asset, atSeconds: 1.0)
        let withoutText = try await FramePixels.capture(asset: asset, atSeconds: 3.0)
        #expect(withText.brightPixelCount(inBandFromY: band.top, toY: band.bottom) > 0, "scaled caption must be burnt in")
        #expect(withoutText.brightPixelCount(inBandFromY: band.top, toY: band.bottom) == 0)
    }

    /// Caption band in top-down pixel coordinates (Core Animation insets are from the bottom).
    static func captionBand(renderHeight: CGFloat, style: SubtitleStyle) -> (top: Int, bottom: Int) {
        let bottom = renderHeight - style.bottomInset
        return (top: Int(bottom - style.bandHeight), bottom: Int(bottom))
    }

    @MainActor
    @Test func previewPlaysTheCutCompositionWithoutWritingAFile() async throws {
        let dir = try SyntheticMedia.scratchDirectory("preview")
        let source = try await Self.makeSource(dir: dir, seconds: 8)
        let cues = [
            SRTCue(index: 1, start: 1.5, end: 2.5, text: "第一段"),
            SRTCue(index: 2, start: 3.5, end: 4.5, text: "被删掉的间隙"),
            SRTCue(index: 3, start: 5.0, end: 6.0, text: "第二段"),
        ]
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path)

        let preview = try await ClipRenderer().preview(sourceURL: source, clip: try Self.clip(), cues: cues)

        // Kept segments 1–3 s and 5–7 s → 4 s of output; the gap cue is dropped, the rest remapped.
        #expect(preview.durationSec == 4)
        #expect(preview.subtitles == [
            SubtitleWindow(text: "第一段", start: 0.5, end: 1.5),
            SubtitleWindow(text: "第二段", start: 2.0, end: 3.0),
        ])
        #expect(preview.renderSize == CGSize(width: 640, height: 360))
        let duration = try await preview.playerItem.asset.load(.duration)
        #expect(abs(duration.seconds - 4) < 0.05)
        #expect(preview.playerItem.videoComposition?.renderSize == CGSize(width: 640, height: 360))
        // Nothing exported: previewing must not touch the disk.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == before)
    }

    @Test func sourceWithoutVideoTrackIsAnError() async throws {
        let dir = try SyntheticMedia.scratchDirectory("novideo")
        let tone = dir.appending(path: "tone.m4a")
        try SyntheticMedia.makeToneAudio(at: tone, durationSec: 2)
        await #expect(throws: ClipRendererError.noVideoTrack(tone)) {
            try await ClipRenderer().render(sourceURL: tone, clip: try Self.clip(), cues: [], outputURL: dir.appending(path: "o.mp4")) { _ in }
        }
    }
}

/// RGBA bytes of one decoded frame, for coarse semantic checks.
struct FramePixels {
    let width: Int, height: Int, bytes: [UInt8]

    static func capture(asset: AVAsset, atSeconds seconds: Double) async throws -> FramePixels {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info)
            else { throw ClipRendererError.exportSessionUnavailable }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return FramePixels(width: width, height: height, bytes: bytes)
    }

    func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    func isBluish(x: Int, y: Int) -> Bool {
        let (r, g, b) = rgb(x: x, y: y)
        return b > 100 && r < 80 && g < 80
    }

    /// Pixels in the horizontal band that are clearly not the deep-blue background (text fill or stroke).
    func brightPixelCount(inBandFromY top: Int, toY bottom: Int) -> Int {
        var count = 0
        for y in stride(from: max(0, top), to: min(height, bottom), by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let (r, g, _) = rgb(x: x, y: y)
                if r > 160 && g > 160 { count += 1 }
            }
        }
        return count
    }
}
