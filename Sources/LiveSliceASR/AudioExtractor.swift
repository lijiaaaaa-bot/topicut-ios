// Why: SpeechAnalyzer reads audio files; users pick videos. Exporting the audio track to an
 // `.m4a` first makes the ASR input format uniform and turns "this video has no audio" into a
 // typed error. Optional start/duration windows let language detection skip silent intros.

import AVFoundation
import Foundation

public enum AudioExtractorError: Error, Equatable, Sendable {
    /// The media has no audio track; there is nothing to transcribe.
    case noAudioTrack(URL)
    case exportSessionUnavailable
    /// The requested window is past the end of the audio.
    case emptyTimeRange
}

public enum AudioExtractor {
    /// Exports the first audio track of `mediaURL` into an AAC `.m4a` at `outputURL` (overwritten).
    /// `startSec` / `maximumDurationSec` select a window for language probes.
    public static func extractAudio(
        from mediaURL: URL,
        to outputURL: URL,
        startSec: Double = 0,
        maximumDurationSec: Double? = nil
    ) async throws {
        let asset = AVURLAsset(url: mediaURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else { throw AudioExtractorError.noAudioTrack(mediaURL) }
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw AudioExtractorError.exportSessionUnavailable }
        let full = try await asset.load(.duration)
        let timescale = full.timescale == 0 ? CMTimeScale(600) : full.timescale
        let start = CMTime(seconds: max(0, startSec), preferredTimescale: timescale)
        guard start < full else { throw AudioExtractorError.emptyTimeRange }
        let remaining = full - start
        let duration: CMTime
        if let maximumDurationSec {
            let cap = CMTime(seconds: maximumDurationSec, preferredTimescale: timescale)
            duration = CMTimeMinimum(remaining, cap)
        } else {
            duration = remaining
        }
        guard duration.seconds > 0.05 else { throw AudioExtractorError.emptyTimeRange }
        try compositionTrack.insertTimeRange(CMTimeRange(start: start, duration: duration), of: audioTrack, at: .zero)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioExtractorError.exportSessionUnavailable
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try await session.export(to: outputURL, as: .m4a)
    }
}
