// Why: live preview shares export framing geometry (ADR-0014 / 0025 / 0027) without burning captions.

import AVFoundation
import Foundation
import LiveSliceCore

extension ClipRenderer {
    /// Builds the same composition the export uses, but hands it to a player instead of a file.
    /// Returns in well under a second for any clip length; nothing is decoded until playback.
    /// `words` (when present) become word-timed captions for the `.highlightWord` overlay; without
    /// them that style is unavailable on the stage, same as on export. Main actor because
    /// `AVPlayerItem.init(asset:)` is.
    @MainActor
    public func preview(
        sourceURL: URL, clip: EDLClip, cues: [SRTCue], words: [TimedToken]? = nil
    ) async throws -> ClipPreview {
        await SourceMediaGate.shared.acquire()
        do {
            let built = try await previewExclusive(
                sourceURL: sourceURL, clip: clip, cues: cues, words: words
            )
            await SourceMediaGate.shared.release()
            return built
        } catch {
            await SourceMediaGate.shared.release()
            throw error
        }
    }

    @MainActor
    private func previewExclusive(
        sourceURL: URL, clip: EDLClip, cues: [SRTCue], words: [TimedToken]?
    ) async throws -> ClipPreview {
        let timeline = try ClipTimeline(clip: clip)
        guard timeline.totalDuration > 0 else { throw ClipRendererError.emptyTimeline(clipID: clip.id) }
        let source = try await SourceInfo.load(url: sourceURL)
        let oriented = VerticalFrame.orientedSize(naturalSize: source.naturalSize, preferredTransform: source.preferredTransform)
        let renderSize = options.framingMode.renderSize(orientedSource: oriented)
        let (composition, videoTrack) = try Self.buildComposition(source: source, timeline: timeline)
        switch options.framingMode {
        case .sourceAspect:
            // No video composition for source-aspect playback: the track's own transform orients
            // the frames and the player layer scales them (ADR-0014).
            videoTrack.preferredTransform = source.preferredTransform
        case .phonePortrait, .portraitFit:
            // WYSIWYG: same crop/fit transform as export, without burning captions (overlay still paints them).
            let focus = try await framingFocus(source: source, clip: clip)
            let videoComposition = try buildVideoComposition(
                source: source, track: videoTrack, duration: composition.duration,
                captions: Captions.none, renderSize: renderSize, focus: focus
            )
            let item = AVPlayerItem(asset: composition)
            item.videoComposition = videoComposition
            let wordCaptions: [WordCaption]?
            if let words {
                wordCaptions = try timeline.wordCaptions(for: cues, words: words)
            } else {
                wordCaptions = nil
            }
            return ClipPreview(
                playerItem: item, subtitles: timeline.subtitleWindows(for: cues), wordCaptions: wordCaptions,
                renderSize: renderSize, durationSec: timeline.totalDuration, source: source
            )
        }
        let item = AVPlayerItem(asset: composition)
        let wordCaptions: [WordCaption]?
        if let words {
            wordCaptions = try timeline.wordCaptions(for: cues, words: words)
        } else {
            wordCaptions = nil
        }
        return ClipPreview(
            playerItem: item, subtitles: timeline.subtitleWindows(for: cues), wordCaptions: wordCaptions,
            renderSize: renderSize, durationSec: timeline.totalDuration, source: source
        )
    }

}
