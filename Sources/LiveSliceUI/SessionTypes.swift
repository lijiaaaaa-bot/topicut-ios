// Why: the value types the session speaks in — pipeline stage, per-clip export state, the result,
// the injected dependency closures, and error-to-text — kept apart from the state machine so
// SliceSession.swift stays about sequencing and each type is readable on its own.

import Foundation
import LiveSliceASR
import LiveSliceCore

public enum SessionStage: Equatable, Sendable {
    case idle
    case preparingModel(Double)
    case transcribing(Double)
    case slicing
    case ready
    case failed(String)
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
}

public struct SessionDependencies: Sendable {
    public typealias Progress = @Sendable (Double) -> Void

    public var prepareModel: @Sendable (ASRLocalePreference, @escaping Progress) async throws -> Void
    public var transcribe: @Sendable (
        _ media: URL, ASRLocalePreference, _ scratch: URL, @escaping Progress
    ) async throws -> TranscriptionOutcome
    public var slice: @Sendable (_ srt: String, DeepSeekConfiguration) async throws -> EDLDocument
    public var render: @Sendable (
        _ source: URL, EDLClip, [SRTCue], _ output: URL, @escaping Progress
    ) async throws -> URL

    public init(
        prepareModel: @escaping @Sendable (ASRLocalePreference, @escaping Progress) async throws -> Void,
        transcribe: @escaping @Sendable (
            URL, ASRLocalePreference, URL, @escaping Progress
        ) async throws -> TranscriptionOutcome,
        slice: @escaping @Sendable (String, DeepSeekConfiguration) async throws -> EDLDocument,
        render: @escaping @Sendable (URL, EDLClip, [SRTCue], URL, @escaping Progress) async throws -> URL
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
