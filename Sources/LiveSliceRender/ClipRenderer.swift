// Why: executes one EDL clip against the source and writes an MP4 (cut, concat, burnt-in captions).
// FramingMode chooses source aspect (ADR-0014) or phone 9:16 face crop (ADR-0025). Never re-slices.

import AVFoundation
import Foundation
import LiveSliceCore

public enum ClipRendererError: Error, Equatable, Sendable {
    case noVideoTrack(URL)
    case compositionTrackUnavailable
    case exportSessionUnavailable
    case emptyTimeline(clipID: String)
    /// Word-highlight captions without saved word timings (pre-ADR-0023). Not downgraded.
    case wordTimingsUnavailable(clipID: String)
}

public struct RenderOptions: Sendable, Equatable {
    public let frameRate: Int32
    public let captionStyle: CaptionStyle
    public let captionPosition: CaptionPosition
    /// Free band / scale / colours (ADR-0027); overrides captionPosition geometry when burning in.
    public let captionTune: CaptionTune
    public let framingMode: FramingMode
    /// When set in phonePortrait, skips Vision and uses this normalised focus (ADR-0026).
    public let cropFocus: CGPoint?
    /// ≥1; tightens the 9:16 window around cropFocus / auto focus (ADR-0026).
    public let cropZoom: CGFloat
    /// Reference for a 1080×1920 canvas; tune replaces bottomInset after scaling.
    public let subtitleStyle: SubtitleStyle

    public init(
        frameRate: Int32, captionStyle: CaptionStyle, captionPosition: CaptionPosition = .bottom,
        captionTune: CaptionTune = .standard,
        framingMode: FramingMode = .sourceAspect, cropFocus: CGPoint? = nil, cropZoom: CGFloat = 1,
        subtitleStyle: SubtitleStyle = .vertical1080p
    ) {
        self.frameRate = frameRate
        self.captionStyle = captionStyle
        self.captionPosition = captionPosition
        self.captionTune = captionTune
        self.framingMode = framingMode
        self.cropFocus = cropFocus
        self.cropZoom = max(1, cropZoom)
        self.subtitleStyle = subtitleStyle
    }

    public static let standard = RenderOptions(frameRate: 30, captionStyle: .clean, captionPosition: .bottom)

    public static func standard(
        captionStyle: CaptionStyle, position: CaptionPosition = .bottom,
        tune: CaptionTune = .standard, framing: FramingMode = .sourceAspect,
        cropFocus: CGPoint? = nil, cropZoom: CGFloat = 1
    ) -> RenderOptions {
        RenderOptions(
            frameRate: 30, captionStyle: captionStyle, captionPosition: position,
            captionTune: tune, framingMode: framing, cropFocus: cropFocus, cropZoom: cropZoom
        )
    }
}

public struct RenderResult: Sendable, Equatable {
    public let outputURL: URL
    public let durationSec: Double
    public let renderSize: CGSize
    public let subtitleCount: Int
}

/// A clip playable immediately, without an export: the cut/concat composition as an `AVPlayerItem`,
/// plus caption windows (composition time) for a live overlay. Burning captions into an MP4 is a
/// separate export step; the overlay only shows the current look/position so the user can see them
/// while watching (ADR-0024). `AVVideoComposition.animationTool` is export-only.
public struct ClipPreview: @unchecked Sendable {
    public let playerItem: AVPlayerItem
    /// Plain cue windows (composition time); used by `.clean`.
    public let subtitles: [SubtitleWindow]
    /// Word-timed captions when the project has `words.json`; nil for 1.0 transcriptions.
    public let wordCaptions: [WordCaption]?
    public let renderSize: CGSize
    public let durationSec: Double
    /// Kept alive on purpose (see SourceInfo).
    let source: SourceInfo

    /// Captions for the current look. `.highlightWord` without word timings throws; `.none` hides the overlay.
    public func captions(style: CaptionStyle, clipID: String) throws -> PlaybackCaptions {
        switch style {
        case .none: return .none
        case .clean: return .plain(subtitles)
        case .highlightWord:
            guard let wordCaptions else { throw ClipRendererError.wordTimingsUnavailable(clipID: clipID) }
            return .words(wordCaptions)
        }
    }
}

public struct ClipRenderer: Sendable {
    public let options: RenderOptions

    public init(options: RenderOptions = .standard) {
        self.options = options
    }

    /// Renders `clip` from `sourceURL` into `outputURL` (overwritten). `progress` receives 0…1.
    /// `words` are the transcript's timed tokens; required only by `.highlightWord`.
    public func render(
        sourceURL: URL, clip: EDLClip, cues: [SRTCue], words: [TimedToken]? = nil, outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> RenderResult {
        let timeline = try ClipTimeline(clip: clip)
        guard timeline.totalDuration > 0 else { throw ClipRendererError.emptyTimeline(clipID: clip.id) }
        let captions = try captions(timeline: timeline, clip: clip, cues: cues, words: words)
        let source = try await SourceInfo.load(url: sourceURL)
        let oriented = VerticalFrame.orientedSize(naturalSize: source.naturalSize, preferredTransform: source.preferredTransform)
        let renderSize = options.framingMode.renderSize(orientedSource: oriented)
        let focus = try await framingFocus(source: source, clip: clip)
        let (composition, videoTrack) = try Self.buildComposition(source: source, timeline: timeline)
        let videoComposition = try buildVideoComposition(
            source: source, track: videoTrack, duration: composition.duration,
            captions: captions, renderSize: renderSize, focus: focus
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
            renderSize: renderSize, subtitleCount: captions.count
        )
    }

    /// What gets burnt in, per the chosen style.
    enum Captions {
        case none
        case plain([SubtitleWindow])
        case words([WordCaption])

        var count: Int {
            switch self {
            case .none: 0
            case .plain(let windows): windows.count
            case .words(let captions): captions.count
            }
        }
    }

    private func captions(timeline: ClipTimeline, clip: EDLClip, cues: [SRTCue], words: [TimedToken]?) throws -> Captions {
        switch options.captionStyle {
        case .none: return .none
        case .clean: return .plain(timeline.subtitleWindows(for: cues))
        case .highlightWord:
            guard let words else { throw ClipRendererError.wordTimingsUnavailable(clipID: clip.id) }
            return .words(try timeline.wordCaptions(for: cues, words: words))
        }
    }

    static func buildComposition(
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

    func framingFocus(source: SourceInfo, clip: EDLClip) async throws -> CGPoint? {
        guard options.framingMode == .phonePortrait else { return nil }
        if let override = options.cropFocus { return override }
        return try await FaceSampler.focus(
            asset: source.asset, preferredTransform: source.preferredTransform, naturalSize: source.naturalSize,
            startSec: clip.startSec, endSec: clip.endSec
        )
    }

    func buildVideoComposition(
        source: SourceInfo, track: AVMutableCompositionTrack, duration: CMTime,
        captions: Captions, renderSize: CGSize, focus: CGPoint?
    ) throws -> AVMutableVideoComposition {
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let oriented = VerticalFrame.orientedSize(naturalSize: source.naturalSize, preferredTransform: source.preferredTransform)
        let transform: CGAffineTransform
        switch options.framingMode {
        case .sourceAspect, .portraitFit:
            transform = VerticalFrame.fitTransform(
                naturalSize: source.naturalSize, preferredTransform: source.preferredTransform, renderSize: renderSize
            )
        case .phonePortrait:
            let window = FaceFocus.phoneCropWindow(
                oriented: oriented, focus: focus ?? CGPoint(x: 0.5, y: 0.5), zoom: options.cropZoom
            )
            transform = VerticalFrame.fillTransform(
                naturalSize: source.naturalSize, preferredTransform: source.preferredTransform,
                cropWindow: window, renderSize: renderSize
            )
        }
        layerInstruction.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: options.frameRate)
        videoComposition.instructions = [instruction]
        let style = options.captionTune.style(from: options.subtitleStyle, renderSize: renderSize)
        let textColor = try options.captionTune.textCGColor()
        let accentColor = try options.captionTune.accentCGColor()
        switch captions {
        case .none: break
        case .plain(let windows) where windows.isEmpty: break
        case .words(let list) where list.isEmpty: break
        case .plain(let windows):
            videoComposition.animationTool = try SubtitleLayerBuilder.animationTool(
                windows: windows, renderSize: renderSize, style: style, fill: textColor
            )
        case .words(let list):
            videoComposition.animationTool = try SubtitleLayerBuilder.animationTool(
                captions: list, renderSize: renderSize, style: style, fill: textColor, accent: accentColor
            )
        }
        return videoComposition
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
