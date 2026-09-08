// Why: the app needs three user-owned settings — the AI service key (Keychain only, ADR-0007),
// the service endpoint/model (a preset or custom, ADR-0018), and the ASR locale preference
// (`auto` or a fixed locale, ADR-0013). Keeping them in one observable object gives settings and
// the pipeline one source of truth.

import Foundation
import LiveSliceASR
import LiveSliceCore
import LiveSliceKeychain
import Observation

@MainActor
@Observable
public final class AppSettings {
    public static let defaultLocaleIdentifier = ASRLocalePreference.automaticIdentifier

    public var apiKey: String
    public var baseURL: String { didSet { defaults.set(baseURL, forKey: Keys.baseURL) } }
    public var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    public var localeIdentifier: String { didSet { defaults.set(localeIdentifier, forKey: Keys.locale) } }

    private let store: APIKeyStore
    private let defaults: UserDefaults

    /// Defaults keys keep their original names so values saved by earlier builds are still read.
    private enum Keys {
        static let baseURL = "deepseek.baseURL"
        static let model = "deepseek.model"
        static let locale = "asr.locale"
    }

    /// Loads persisted values. A Keychain read failure is surfaced to the caller, not hidden.
    public init(store: APIKeyStore = .liveSlice, defaults: UserDefaults = .standard) throws {
        self.store = store
        self.defaults = defaults
        // No item in the Keychain is a legitimate first-launch state; it becomes an error only when slicing starts.
        if let stored = try store.load() { apiKey = stored } else { apiKey = "" }
        baseURL = defaults.string(forKey: Keys.baseURL) ?? DeepSeekConfiguration.defaultBaseURL
        model = defaults.string(forKey: Keys.model) ?? DeepSeekConfiguration.defaultModel
        localeIdentifier = defaults.string(forKey: Keys.locale) ?? Self.defaultLocaleIdentifier
    }

    public var localePreference: ASRLocalePreference { ASRLocalePreference(identifier: localeIdentifier) }

    /// Fixed locales only; `auto` has no single Locale.
    public var locale: Locale? {
        if case .fixed(let locale) = localePreference { return locale }
        return nil
    }

    /// The preset whose endpoint is in use, or nil when the endpoint was typed by hand.
    public var servicePreset: AIServicePreset? { AIServicePreset.matching(baseURL: baseURL) }

    /// Switches endpoint and model to a preset in one step. The key is left alone: it belongs to
    /// the user, and whether it fits the new service is for the next real call to decide.
    public func apply(_ preset: AIServicePreset) {
        baseURL = preset.baseURL
        model = preset.model
    }

    /// Persists the key in the Keychain (deleting the item when cleared).
    public func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try store.delete() } else { try store.save(trimmed) }
        apiKey = trimmed
    }

    /// Configuration for the LLM call; throws `DeepSeekError.missingAPIKey` when no key is stored.
    public func deepSeekConfiguration() throws -> DeepSeekConfiguration {
        try DeepSeekConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
    }
}
