// Why: the on-device ASR adapter decided in ADR-0002. It wraps SpeechAnalyzer/SpeechTranscriber
// (iOS 26 / macOS 26), installs the locale model when needed, and turns timed word runs into SRT
// cues. Automatic locale preference (ADR-0013) probes zh_CN + en_US before the full pass so English
// audio is never fed to the Chinese model. Audio never leaves the device; unavailability is typed.

import AVFoundation
import Foundation
import LiveSliceCore
import Speech

public enum SpeechTranscriptionError: Error, Equatable, Sendable, LocalizedError {
    /// `SpeechTranscriber.isAvailable` is false on this device.
    case recognizerUnavailable
    /// The requested locale is not in `SpeechTranscriber.supportedLocales`.
    case localeUnsupported(String)
    /// Recognition finished with zero timed tokens / no letter characters in probe windows.
    case noSpeechDetected

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "此设备无法使用端侧语音识别"
        case .localeUnsupported(let id):
            return "不支持的语音语言（\(id)）"
        case .noSpeechDetected:
            return "没有检测到人声。若片头是音乐或静音，已自动往后找；仍失败时可在设置里手动选语言后重试"
        }
    }
}

public enum SpeechAssetState: Equatable, Sendable {
    case installed
    case downloadable
    case downloading
    case unsupported
}

/// Cues plus the locale that actually produced them (after automatic detection when requested).
public struct TranscriptionOutcome: Equatable, Sendable {
    public let cues: [SRTCue]
    public let locale: Locale

    public init(cues: [SRTCue], locale: Locale) {
        self.cues = cues
        self.locale = locale
    }
}

public struct SpeechTranscriptionService: Sendable {
    public let locale: Locale
    public let policy: CueSegmenterPolicy

    public init(locale: Locale, policy: CueSegmenterPolicy? = nil) {
        self.locale = locale
        self.policy = policy ?? .forLocale(locale)
    }

    /// Locales the transcriber supports on this OS, e.g. `zh_CN`, `en_US`.
    public static func supportedLocaleIdentifiers() async -> [String] {
        await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
    }

    /// Whether the model for `locale` is installed, downloadable, or unsupported.
    public func assetState() async throws -> SpeechAssetState {
        let transcriber = try await makeTranscriber()
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .installed
        case .supported: return .downloadable
        case .downloading: return .downloading
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Downloads and installs the locale model if it is not present. `progress` receives 0…1.
    public func installAssetsIfNeeded(progress: @escaping @Sendable (Double) -> Void) async throws {
        let transcriber = try await makeTranscriber()
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            progress(1)
            return
        }
        let observer = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { value, _ in
            progress(value.fractionCompleted)
        }
        defer { observer.invalidate() }
        try await request.downloadAndInstall()
        progress(1)
    }

    /// Installs every locale automatic mode may need (zh_CN + en_US), or just the fixed one.
    public static func installAssets(
        for preference: ASRLocalePreference, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch preference {
        case .fixed(let locale):
            try await SpeechTranscriptionService(locale: locale).installAssetsIfNeeded(progress: progress)
        case .automatic:
            let locales = await SpeechLanguageDetector.candidateLocales()
            guard !locales.isEmpty else {
                throw SpeechTranscriptionError.localeUnsupported(ASRLocalePreference.automaticIdentifier)
            }
            for (index, locale) in locales.enumerated() {
                let base = Double(index) / Double(locales.count)
                let span = 1 / Double(locales.count)
                try await SpeechTranscriptionService(locale: locale).installAssetsIfNeeded { value in
                    progress(base + value * span)
                }
            }
            progress(1)
        }
    }

    /// Resolves preference → locale, extracts audio once, probes when automatic, then full-file ASR.
    public static func transcribe(
        mediaURL: URL,
        preference: ASRLocalePreference,
        scratchDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionOutcome {
        let audioURL = scratchDirectory.appending(path: "asr-input-\(UUID().uuidString).m4a")
        try await AudioExtractor.extractAudio(from: mediaURL, to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) } // guard-allow: silent-fallback scratch-cleanup-cannot-affect-the-result

        let locale: Locale
        switch preference {
        case .fixed(let fixed):
            locale = fixed
            progress(0.05)
        case .automatic:
            locale = try await resolveAutomaticLocale(fullAudioURL: audioURL, scratchDirectory: scratchDirectory)
            progress(0.12)
        }

        let cues = try await SpeechTranscriptionService(locale: locale)
            .transcribe(audioURL: audioURL) { value in progress(0.12 + value * 0.88) }
        return TranscriptionOutcome(cues: cues, locale: locale)
    }

    /// Extracts the audio track of a video/audio file into `scratchDirectory`, then transcribes it.
    public func transcribe(
        mediaURL: URL, scratchDirectory: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SRTCue] {
        let audioURL = scratchDirectory.appending(path: "asr-input-\(UUID().uuidString).m4a")
        try await AudioExtractor.extractAudio(from: mediaURL, to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) } // guard-allow: silent-fallback scratch-cleanup-cannot-affect-the-result
        return try await transcribe(audioURL: audioURL, progress: progress)
    }

    /// Runs the whole file through SpeechAnalyzer and returns subtitle-shaped cues.
    /// `progress` is the fraction of audio whose results have been finalized.
    public func transcribe(audioURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [SRTCue] {
        let transcriber = try await makeTranscriber()
        let file = try AVAudioFile(forReading: audioURL)
        let totalSeconds = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let collected: [TimedToken] = collectTokens(from: transcriber, totalSeconds: totalSeconds, progress: progress)
        let lastSample = try await analyzer.analyzeSequence(from: file)
        if let lastSample {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        let tokens = try await collected
        guard !tokens.isEmpty else { throw SpeechTranscriptionError.noSpeechDetected }
        let cues = try CueSegmenter.cues(from: tokens, policy: policy)
        guard !cues.isEmpty else { throw SpeechTranscriptionError.noSpeechDetected }
        progress(1)
        return cues
    }

    private static func resolveAutomaticLocale(fullAudioURL: URL, scratchDirectory: URL) async throws -> Locale {
        try await SpeechLanguageDetector.detect(fullAudioURL: fullAudioURL, scratchDirectory: scratchDirectory)
    }

    private func makeTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw SpeechTranscriptionError.recognizerUnavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechTranscriptionError.localeUnsupported(locale.identifier)
        }
        return SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange]
        )
    }

    private func collectTokens(
        from transcriber: SpeechTranscriber, totalSeconds: Double, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedToken] {
        var tokens: [TimedToken] = []
        var untimedPrefix = ""
        for try await result in transcriber.results {
            for run in result.text.runs {
                let text = String(result.text[run.range].characters)
                if let range = run.audioTimeRange {
                    tokens.append(TimedToken(text: untimedPrefix + text, start: range.start.seconds, end: range.end.seconds))
                    untimedPrefix = ""
                } else if let last = tokens.popLast() {
                    // Punctuation and spaces carry no time range: glue them to the preceding word.
                    tokens.append(TimedToken(text: last.text + text, start: last.start, end: last.end))
                } else {
                    untimedPrefix += text
                }
            }
            if totalSeconds > 0 { progress(min(1, result.range.end.seconds / totalSeconds)) }
        }
        return tokens
    }
}
