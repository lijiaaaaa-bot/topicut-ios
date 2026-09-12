// Why: the value types the session speaks in — pipeline stage, per-clip export state, the result,
// the injected dependency closures, and error-to-text — kept apart from the state machine so
// SliceSession.swift stays about sequencing and each type is readable on its own.

import Foundation
import LLMKit
import LiveSliceASR
import LiveSliceCore
import LiveSliceRender
import CoreGraphics

public enum SessionStage: Equatable, Sendable {
    case idle
    case preparingModel(Double)
    case transcribing(Double)
    /// Transcript is saved; user sets taste in 切片工作室 then explicitly starts the AI call (ADR-0028).
    case awaitingSlice
    case slicing
    case ready
    case failed(String)
}

/// What the 切片工作室 needs after ASR and before the paid slice call.
public struct AwaitingSliceInfo: Equatable, Sendable {
    public let projectID: String
    public let sourceURL: URL
    public let cueCount: Int
    public let localeIdentifier: String
    public let hasWords: Bool

    public init(projectID: String, sourceURL: URL, cueCount: Int, localeIdentifier: String, hasWords: Bool) {
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.cueCount = cueCount
        self.localeIdentifier = localeIdentifier
        self.hasWords = hasWords
    }
}

public enum ClipRenderState: Equatable, Sendable {
    case idle
    case rendering(Double)
    case done(URL)
    case failed(String)
}

public struct SessionResult: Equatable, Sendable {
    public let projectID: String
    public let sourceURL: URL
    public let cues: [SRTCue]
    public let document: EDLDocument
    public let localeIdentifier: String
    /// `model|baseURL` that produced the EDL (nil on records from before provenance was stored);
    /// tells the cost estimate whether the call went to a service with a known price sheet.
    public let slicedWith: String?
    /// Timed words the cues came from; nil for projects transcribed before ADR-0024 (no
    /// word-highlight captions for them until re-transcribed).
    public let words: [TimedToken]?

    public init(
        projectID: String, sourceURL: URL, cues: [SRTCue], document: EDLDocument, localeIdentifier: String,
        slicedWith: String?, words: [TimedToken]? = nil
    ) {
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.cues = cues
        self.document = document
        self.localeIdentifier = localeIdentifier
        self.slicedWith = slicedWith
        self.words = words
    }
}

public struct SessionDependencies: Sendable {
    public typealias Progress = @Sendable (Double) -> Void

    public var prepareModel: @Sendable (ASRLocalePreference, @escaping Progress) async throws -> Void
    public var transcribe: @Sendable (
        _ media: URL, ASRLocalePreference, _ scratch: URL, @escaping Progress
    ) async throws -> TranscriptionOutcome
    public var slice: @Sendable (_ srt: String, DeepSeekConfiguration, SlicingTaste) async throws -> EDLDocument
    public var render: @Sendable (
        _ source: URL, EDLClip, [SRTCue], _ words: [TimedToken]?, CaptionStyle, CaptionPosition, CaptionTune, FramingMode,
        _ cropFocus: CGPoint?, _ cropZoom: CGFloat, _ output: URL, @escaping Progress
    ) async throws -> URL

    public init(
        prepareModel: @escaping @Sendable (ASRLocalePreference, @escaping Progress) async throws -> Void,
        transcribe: @escaping @Sendable (
            URL, ASRLocalePreference, URL, @escaping Progress
        ) async throws -> TranscriptionOutcome,
        slice: @escaping @Sendable (String, DeepSeekConfiguration, SlicingTaste) async throws -> EDLDocument,
        render: @escaping @Sendable (
            URL, EDLClip, [SRTCue], [TimedToken]?, CaptionStyle, CaptionPosition, CaptionTune, FramingMode, CGPoint?, CGFloat, URL,
            @escaping Progress
        ) async throws -> URL
    ) {
        self.prepareModel = prepareModel
        self.transcribe = transcribe
        self.slice = slice
        self.render = render
    }
}

public enum ErrorText {
    public static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        let typed = String(describing: error)
        let message = error.localizedDescription
        // Foundation's generic "couldn't be completed" adds nothing to a typed case name.
        if message.contains("completed") || typed.contains(message) { return typed }
        return "\(typed) — \(message)"
    }
}
