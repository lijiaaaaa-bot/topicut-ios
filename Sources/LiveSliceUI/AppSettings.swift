// Why: the app needs five user-owned settings — the AI service key (Keychain only, ADR-0007),
// the service endpoint/model (a preset or custom, ADR-0018), the ASR locale preference
// (`auto` or a fixed locale, ADR-0013), and the export caption look + band position (ADR-0024).
// Keeping them in one observable object gives settings and the pipeline one source of truth.

import Foundation
import LLMKit
import LiveSliceASR
import LiveSliceCore
import LiveSliceKeychain
import LiveSliceRender
import Observation

@MainActor
@Observable
public final class AppSettings {
    public static let defaultLocaleIdentifier = ASRLocalePreference.automaticIdentifier

    public var apiKey: String
    public var baseURL: String { didSet { defaults.set(baseURL, forKey: Keys.baseURL) } }
    public var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    public var localeIdentifier: String { didSet { defaults.set(localeIdentifier, forKey: Keys.locale) } }
    /// Caption look for the live preview and (when not `.none`) burnt into exports.
    public var captionStyle: CaptionStyle { didSet { defaults.set(captionStyle.rawValue, forKey: Keys.captionStyle) } }
    /// Where the caption band sits; preview and burn share it.
    public var captionPosition: CaptionPosition {
        didSet { defaults.set(captionPosition.rawValue, forKey: Keys.captionPosition) }
    }
    /// Free caption band / scale / colours (ADR-0027).
    public var captionTune: CaptionTune {
        didSet {
            defaults.set(captionTune.bandY, forKey: Keys.tuneBandY)
            defaults.set(captionTune.fontScale, forKey: Keys.tuneFontScale)
            defaults.set(captionTune.textHex, forKey: Keys.tuneTextHex)
            defaults.set(captionTune.accentHex, forKey: Keys.tuneAccentHex)
        }
    }
    /// Source aspect, phone crop, or letterboxed 9:16.
    public var framingMode: FramingMode {
        didSet { defaults.set(framingMode.rawValue, forKey: Keys.framingMode) }
    }
    /// Topic density + highlight length band (ADR-0026); changes invalidate the EDL via sliceKey.
    public var slicingTaste: SlicingTaste {
        didSet {
            defaults.set(slicingTaste.topicDensity.rawValue, forKey: Keys.topicDensity)
            defaults.set(slicingTaste.highlightSpan.rawValue, forKey: Keys.highlightSpan)
        }
    }

    private let store: APIKeyStore
    private let defaults: UserDefaults

    private enum Keys {
        static let baseURL = "deepseek.baseURL"
        static let model = "deepseek.model"
        static let locale = "asr.locale"
        static let captionStyle = "export.captionStyle"
        static let captionPosition = "export.captionPosition"
        static let tuneBandY = "export.tune.bandY"
        static let tuneFontScale = "export.tune.fontScale"
        static let tuneTextHex = "export.tune.textHex"
        static let tuneAccentHex = "export.tune.accentHex"
        static let framingMode = "export.framingMode"
        static let topicDensity = "slice.topicDensity"
        static let highlightSpan = "slice.highlightSpan"
    }

    public init(store: APIKeyStore = .liveSlice, defaults: UserDefaults = .standard) throws {
        self.store = store
        self.defaults = defaults
        if let stored = try store.load() { apiKey = stored } else { apiKey = "" }
        baseURL = defaults.string(forKey: Keys.baseURL) ?? DeepSeekConfiguration.defaultBaseURL
        model = defaults.string(forKey: Keys.model) ?? DeepSeekConfiguration.defaultModel
        localeIdentifier = defaults.string(forKey: Keys.locale) ?? Self.defaultLocaleIdentifier
        captionStyle = try Self.loadCaptionStyle(defaults)
        let position = try Self.loadCaptionPosition(defaults)
        captionPosition = position
        captionTune = try Self.loadCaptionTune(defaults, fallbackPosition: position)
        framingMode = try Self.loadFraming(defaults)
        slicingTaste = try Self.loadTaste(defaults)
    }

    private static func loadCaptionStyle(_ defaults: UserDefaults) throws -> CaptionStyle {
        guard let stored = defaults.string(forKey: Keys.captionStyle) else { return .clean }
        guard let style = CaptionStyle(rawValue: stored) else { throw AppSettingsError.unknownCaptionStyle(stored) }
        return style
    }

    private static func loadCaptionPosition(_ defaults: UserDefaults) throws -> CaptionPosition {
        guard let stored = defaults.string(forKey: Keys.captionPosition) else { return .bottom }
        guard let position = CaptionPosition(rawValue: stored) else {
            throw AppSettingsError.unknownCaptionPosition(stored)
        }
        return position
    }

    private static func loadCaptionTune(_ defaults: UserDefaults, fallbackPosition: CaptionPosition) throws -> CaptionTune {
        guard defaults.object(forKey: Keys.tuneBandY) != nil else { return .from(position: fallbackPosition) }
        let bandY = defaults.double(forKey: Keys.tuneBandY)
        let fontScale = defaults.double(forKey: Keys.tuneFontScale)
        guard let textHex = defaults.string(forKey: Keys.tuneTextHex) else { throw AppSettingsError.corruptCaptionTune }
        guard let accentHex = defaults.string(forKey: Keys.tuneAccentHex) else { throw AppSettingsError.corruptCaptionTune }
        let tune = CaptionTune(bandY: bandY, fontScale: fontScale, textHex: textHex, accentHex: accentHex)
        do {
            _ = try tune.textCGColor()
            _ = try tune.accentCGColor()
        } catch {
            throw AppSettingsError.corruptCaptionTune
        }
        return tune
    }

    private static func loadFraming(_ defaults: UserDefaults) throws -> FramingMode {
        guard let stored = defaults.string(forKey: Keys.framingMode) else { return .sourceAspect }
        guard let framing = FramingMode(rawValue: stored) else { throw AppSettingsError.unknownFramingMode(stored) }
        return framing
    }

    private static func loadTaste(_ defaults: UserDefaults) throws -> SlicingTaste {
        let densityRaw = defaults.string(forKey: Keys.topicDensity)
        let spanRaw = defaults.string(forKey: Keys.highlightSpan)
        if densityRaw == nil, spanRaw == nil { return .standard }
        guard let densityRaw else { throw AppSettingsError.unknownTopicDensity("missing") }
        guard let density = TopicDensity(rawValue: densityRaw) else {
            throw AppSettingsError.unknownTopicDensity(densityRaw)
        }
        guard let spanRaw else { throw AppSettingsError.unknownHighlightSpan("missing") }
        guard let span = HighlightSpan(rawValue: spanRaw) else {
            throw AppSettingsError.unknownHighlightSpan(spanRaw)
        }
        return SlicingTaste(topicDensity: density, highlightSpan: span)
    }

    public var localePreference: ASRLocalePreference { ASRLocalePreference(identifier: localeIdentifier) }

    public var locale: Locale? {
        if case .fixed(let locale) = localePreference { return locale }
        return nil
    }

    public var servicePreset: AIServicePreset? { AIServicePreset.matching(baseURL: baseURL) }

    public func apply(_ preset: AIServicePreset) {
        baseURL = preset.baseURL
        model = preset.model
    }

    public func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try store.delete() } else { try store.save(trimmed) }
        apiKey = trimmed
    }

    public func deepSeekConfiguration() throws -> DeepSeekConfiguration {
        try DeepSeekConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
    }
}

public enum AppSettingsError: Error, Equatable, Sendable, LocalizedError {
    case unknownCaptionStyle(String)
    case unknownCaptionPosition(String)
    case unknownFramingMode(String)
    case unknownTopicDensity(String)
    case unknownHighlightSpan(String)
    case corruptCaptionTune

    public var errorDescription: String? {
        switch self {
        case .unknownCaptionStyle(let raw): "未知的字幕样式设置（\(raw)）"
        case .unknownCaptionPosition(let raw): "未知的字幕位置设置（\(raw)）"
        case .unknownFramingMode(let raw): "未知的画幅设置（\(raw)）"
        case .unknownTopicDensity(let raw): "未知的话题密度设置（\(raw)）"
        case .unknownHighlightSpan(let raw): "未知的金句时长设置（\(raw)）"
        case .corruptCaptionTune: "成片字幕微调设置损坏"
        }
    }
}
