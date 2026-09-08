// Why: the renderer decided in ADR-0002/ADR-0004 as `planned`, now real: it executes one EDL clip
// against the source video and writes an MP4 (cut, concat, burnt-in subtitles) in the source's own
// aspect ratio (longest edge capped at 1920). It consumes the EDL contract only; it never
// re-decides what to keep.

import AVFoundation
import Foundation
import LiveSliceCore

public enum ClipRendererError: Error, Equatable, Sendable {
    case noVideoTrack(URL)
    case compositionTrackUnavailable
    case exportSessionUnavailable
    /// The clip's segments sum to zero output time.
    case emptyTimeline(clipID: String)
}

public struct RenderOptions: Sendable, Equatable {
    public let frameRate: Int32
    public let burnSubtitles: Bool
    /// Reference style for a 1080×1920 canvas; scaled to the actual output size at render time.
    public let subtitleStyle: SubtitleStyle

    public init(frameRate: Int32, burnSubtitles: Bool, subtitleStyle: SubtitleStyle) {
        self.frameRate = frameRate
        self.burnSubtitles = burnSubtitles
        self.subtitleStyle = subtitleStyle
    }

    /// The one shape the app ships: source aspect ratio, 30 fps, captions burnt in.
    public static let standard = RenderOptions(frameRate: 30, burnSubtitles: true, subtitleStyle: .vertical1080p)
}

public struct RenderResult: Sendable, Equatable {
    public let outputURL: URL
    public let durationSec: Double
    public let renderSize: CGSize
    public let subtitleCount: Int
}

/// A clip playable immediately, without an export: the cut/concat composition plus the orientation
/// transform as an `AVPlayerItem`, and the subtitle windows (composition time) for a live overlay.
/// `AVVideoComposition.animationTool` is export-only, so captions are not burnt into the preview.
public struct ClipPreview: @unchecked Sendable {
    public let playerItem: AVPlayerItem
    public let subtitles: [SubtitleWindow]
    public let renderSize: CGSize
    public let durationSec: Double
    /// Kept alive on purpose (see SourceInfo).
    let source: SourceInfo
}

public struct ClipRenderer: Sendable {
    public let options: RenderOptions

    public init(options: RenderOptions = .standard) {
        self.options = options
    }

    /// Renders `clip` from `sourceURL` into `outputURL` (overwritten). `progress` receives 0…1.
    public func render(
        sourceURL: URL, clip: EDLClip, cues: [SRTCue], outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> RenderResult {
        let timeline = try ClipTimeline(clip: clip)
        guard timeline.totalDuration > 0 else { throw ClipRendererError.emptyTimeline(clipID: clip.id) }
        let source = try await SourceInfo.load(url: sourceURL)
        let renderSize = resolvedRenderSize(source: source)
        let (composition, videoTrack) = try Self.buildComposition(source: source, timeline: timeline)
        let windows = options.burnSubtitles ? timeline.subtitleWindows(for: cues) : []
        let videoComposition = try buildVideoComposition(
            source: source, track: videoTrack, duration: composition.duration,
            windows: windows, renderSize: renderSize
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipRendererError.exportSessionUnavailable
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }

        let states = session.states(updateInterval: 0.25)
        let monitor = Task {
            for await state in states {
                if case .exporting(let exportProgress) = state { progress(exportProgress.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: outputURL, as: .mp4)
        withExtendedLifetime(source) {} // the source asset must outlive the export (see SourceInfo)
        progress(1)
        return RenderResult(
            outputURL: outputURL, durationSec: timeline.totalDuration,
            renderSize: renderSize, subtitleCount: windows.count
        )
    }

    /// Builds the same composition the export uses, but hands it to a player instead of a file.
    /// Returns in well under a second for any clip length; nothing is decoded until playback.
    /// Main actor because `AVPlayerItem.init(asset:)` is.
    @MainActor
    public func preview(sourceURL: URL, clip: EDLClip, cues: [SRTCue]) async throws -> ClipPreview {
        let timeline = try ClipTimeline(clip: clip)
        guard timeline.totalDuration > 0 else { throw ClipRendererError.emptyTimeline(clipID: clip.id) }
        let source = try await SourceInfo.load(url: sourceURL)
        let renderSize = resolvedRenderSize(source: source)
        let (composition, videoTrack) = try Self.buildComposition(source: source, timeline: timeline)
        let videoComposition = try buildVideoComposition(
            source: source, track: videoTrack, duration: composition.duration, windows: [], renderSize: renderSize
        )
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return ClipPreview(
            playerItem: item, subtitles: timeline.subtitleWindows(for: cues),
            renderSize: renderSize, durationSec: timeline.totalDuration, source: source
        )
    }

    private func resolvedRenderSize(source: SourceInfo) -> CGSize {
        VerticalFrame.sourceRenderSize(
            orientedSize: VerticalFrame.orientedSize(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
        )
    }

    private static func buildComposition(
        source: SourceInfo, timeline: ClipTimeline
    ) throws -> (AVMutableComposition, AVMutableCompositionTrack) {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipRendererError.compositionTrackUnavailable
        }
        var audio: AVMutableCompositionTrack?
        if source.audioTrack != nil {
            audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            guard audio != nil else { throw ClipRendererError.compositionTrackUnavailable }
        }
        for entry in timeline.entries {
            let range = CMTimeRange(start: time(entry.sourceStart), end: time(entry.sourceEnd))
            try video.insertTimeRange(range, of: source.videoTrack, at: time(entry.compositionStart))
            if let audio, let sourceAudio = source.audioTrack {
                try audio.insertTimeRange(range, of: sourceAudio, at: time(entry.compositionStart))
            }
        }
        return (composition, video)
    }

    private func buildVideoComposition(
        source: SourceInfo, track: AVMutableCompositionTrack, duration: CMTime,
        windows: [SubtitleWindow], renderSize: CGSize
    ) throws -> AVMutableVideoComposition {
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let transform = VerticalFrame.fitTransform(
            naturalSize: source.naturalSize,
            preferredTransform: source.preferredTransform,
            renderSize: renderSize
        )
        layerInstruction.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: options.frameRate)
        videoComposition.instructions = [instruction]
        if !windows.isEmpty {
            videoComposition.animationTool = try SubtitleLayerBuilder.animationTool(
                windows: windows, renderSize: renderSize,
                style: options.subtitleStyle.scaled(to: renderSize)
            )
        }
        return videoComposition
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

/// Everything the renderer needs to know about the source, loaded once.
struct SourceInfo: @unchecked Sendable {
    /// Kept alive on purpose: AVAssetTrack only weakly references its asset, and a composition
    /// built from tracks of a deallocated asset exports with an opaque -12780.
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform

    static func load(url: URL) async throws -> SourceInfo {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipRendererError.noVideoTrack(url)
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (naturalSize, transform) = try await video.load(.naturalSize, .preferredTransform)
        return SourceInfo(asset: asset, videoTrack: video, audioTrack: audio, naturalSize: naturalSize, preferredTransform: transform)
    }
}
