// Why: Apple's SpeechTranscriber is per-locale. Feeding English audio to the Chinese model produces
 // garbled Latin (ADR-0013). Automatic mode probes short windows with zh_CN and en_US and picks the
 // locale whose script matches best. Probes run as two separate analyzers (device-reliable) and slide
 // past silent/music intros — empty first-12s must not kill a video that speaks later.

import AVFoundation
import Foundation
import Speech

public enum SpeechLanguageDetector {
    /// Length of one probe window.
    public static let probeSeconds: Double = 12
    /// How far into the file we keep searching before declaring no recognizable speech.
    public static let probeHorizonSeconds: Double = 90
    public static let chinese = Locale(identifier: "zh_CN")
    public static let english = Locale(identifier: "en_US")

    enum ProbeResult: Equatable, Sendable {
        case chinese
        case english
        case empty
    }

    /// Locales automatic mode can choose between (intersection with what this OS supports).
    public static func candidateLocales() async -> [Locale] {
        var result: [Locale] = []
        for candidate in [chinese, english] {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                result.append(supported)
            }
        }
        return result
    }

    /// Scores two probe transcripts. `.empty` means neither produced letter characters.
    static func score(zhText: String, enText: String) -> ProbeResult {
        let zhCJK = cjkRatio(zhText)
        let enLatin = latinRatio(enText)
        if zhCJK <= 0, enLatin <= 0, cjkRatio(enText) <= 0, latinRatio(zhText) <= 0 {
            return .empty
        }
        if zhCJK >= 0.2 { return .chinese }
        if enLatin >= 0.4 { return .english }
        if zhCJK > 0, zhCJK >= enLatin { return .chinese }
        if enLatin > 0 { return .english }
        if cjkRatio(enText) >= 0.2 { return .chinese }
        if latinRatio(zhText) >= 0.4 { return .english }
        return .empty
    }

    /// Picks zh_CN or en_US from two probe transcripts; empty/ambiguous → `noSpeechDetected`.
    public static func choose(zhText: String, enText: String) throws -> Locale {
        switch score(zhText: zhText, enText: enText) {
        case .chinese: return chinese
        case .english: return english
        case .empty: throw SpeechTranscriptionError.noSpeechDetected
        }
    }

    /// Slides 12 s windows across the first `probeHorizonSeconds` until a window has speech.
    public static func detect(fullAudioURL: URL, scratchDirectory: URL) async throws -> Locale {
        let candidates = await candidateLocales()
        guard !candidates.isEmpty else {
            throw SpeechTranscriptionError.localeUnsupported(ASRLocalePreference.automaticIdentifier)
        }
        if candidates.count == 1 { return candidates[0] }

        let duration = try await audioDurationSeconds(fullAudioURL)
        var offset = 0.0
        let horizon = min(duration, probeHorizonSeconds)
        var lastError: Error?
        while offset < horizon {
            let probeURL = scratchDirectory.appending(path: "asr-probe-\(UUID().uuidString).m4a")
            do {
                try await AudioExtractor.extractAudio(
                    from: fullAudioURL, to: probeURL, startSec: offset, maximumDurationSec: probeSeconds
                )
                defer { try? FileManager.default.removeItem(at: probeURL) } // guard-allow: silent-fallback scratch-cleanup-cannot-affect-the-result
                let zhText = try await plainTranscribe(audioURL: probeURL, locale: chinese)
                let enText = try await plainTranscribe(audioURL: probeURL, locale: english)
                switch score(zhText: zhText, enText: enText) {
                case .chinese: return chinese
                case .english: return english
                case .empty: break
                }
            } catch let error as AudioExtractorError where error == .emptyTimeRange {
                break
            } catch {
                lastError = error
            }
            offset += probeSeconds
        }
        if let lastError { throw lastError }
        throw SpeechTranscriptionError.noSpeechDetected
    }

    /// Fraction of letter characters that are CJK (Han / Hiragana / Katakana / Hangul).
    public static func cjkRatio(_ text: String) -> Double {
        scriptRatio(text) { $0.isCJKUnifiedIdeograph || $0.isHiraganaOrKatakana || $0.isHangul }
    }

    /// Fraction of letter characters that are Latin.
    public static func latinRatio(_ text: String) -> Double {
        scriptRatio(text) { $0.isLatinLetter }
    }

    private static func scriptRatio(_ text: String, matches: (Character) -> Bool) -> Double {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        let hits = letters.filter(matches).count
        return Double(hits) / Double(letters.count)
    }

    private static func audioDurationSeconds(_ url: URL) async throws -> Double {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func makeTranscriber(_ locale: Locale) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw SpeechTranscriptionError.recognizerUnavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechTranscriptionError.localeUnsupported(locale.identifier)
        }
        return SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange]
        )
    }

    /// One locale, one analyzer — dual-module probes were empty on device for some files.
    private static func plainTranscribe(audioURL: URL, locale: Locale) async throws -> String {
        let transcriber = try await makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)
        async let text = collectPlainText(from: transcriber)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        return try await text
    }

    private static func collectPlainText(from transcriber: SpeechTranscriber) async throws -> String {
        var parts: [String] = []
        for try await result in transcriber.results {
            parts.append(String(result.text.characters))
        }
        return parts.joined()
    }
}

private extension Character {
    var isLatinLetter: Bool {
        guard let value = unicodeScalars.first?.value else { return false }
        return (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
            || (0x00C0...0x024F).contains(value)
    }

    var isCJKUnifiedIdeograph: Bool {
        guard let value = unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
    }

    var isHiraganaOrKatakana: Bool {
        guard let value = unicodeScalars.first?.value else { return false }
        return (0x3040...0x30FF).contains(value)
    }

    var isHangul: Bool {
        guard let value = unicodeScalars.first?.value else { return false }
        return (0xAC00...0xD7AF).contains(value)
    }
}
