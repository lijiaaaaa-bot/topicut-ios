// Why: the only place the UI layer wires the real modules together (SpeechTranscriptionService,
// TopicSlicer over DeepSeekClient, ClipRenderer). Keeping it in one file makes "what actually runs
// in production" reviewable at a glance and keeps SliceSession free of framework imports.

import Foundation
import LiveSliceASR
import LiveSliceCore
import LiveSliceRender

public extension SessionDependencies {
    /// Production wiring: on-device ASR (with automatic locale), DeepSeek over URLSession, AVFoundation export.
    static func live() -> SessionDependencies {
        SessionDependencies(
            prepareModel: { preference, progress in
                try await SpeechTranscriptionService.installAssets(for: preference, progress: progress)
            },
            transcribe: { media, preference, scratch, progress in
                try await SpeechTranscriptionService.transcribe(
                    mediaURL: media, preference: preference, scratchDirectory: scratch, progress: progress
                )
            },
            slice: { srt, configuration in
                try await TopicSlicer(client: DeepSeekClient(configuration: configuration)).slice(srtText: srt)
            },
            render: { source, clip, cues, output, progress in
                try await ClipRenderer()
                    .render(sourceURL: source, clip: clip, cues: cues, outputURL: output, progress: progress)
                    .outputURL
            }
        )
    }
}

/// Where the app keeps the imported source, intermediate audio, and finished renders. Both live in
/// Caches: they belong to one session, are purged by SliceSession, and must not be backed up.
public enum AppDirectories {
    public static var scratch: URL {
        URL.cachesDirectory.appending(path: "liveslice-scratch")
    }

    public static var renders: URL {
        URL.cachesDirectory.appending(path: "Renders")
    }
}
